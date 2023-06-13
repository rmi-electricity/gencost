# Account for colinearity by fitting PCA components before the clustering
	# Note that in this script we are clustering on a subset of the regression 
	# variables (exclude real_opex);
	# We are also excluding any row where the value for any variable is not within
	# the central 90%

library(tidyverse)
library(skimr)
library(psych)
library(conflicted)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

get_variable_names_with_variance <- function(X){
# Note which columns have variance
	X %>%
		select_if(is.numeric) %>%
		apply(., 2, var, na.rm = T) %>%
		enframe(name = 'variable', value = 'variance') %>%
		filter(!is.na(variance) & (variance > 0)) %>%
		pull(variable)
}

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')
Data <- read_csv('clean_data/data.csv', col_types = c(
	prime_mover = 'c', plant_id_eia = 'f', 
	consolidated_regression_filter = 'l', .default = 'd')) 
variables_for_regressions <- readRDS('clean_data/variables_for_regressions.RDS')
variables_for_clusters <- readRDS('clean_data/variables_for_clusters.RDS')

# Make sure each variable doesn't have a lot of missing instances

# we'll exclude real_opex for having missing data
Data %>%
	select(prime_mover, all_of(variables_for_regressions)) %>%
	gather(variable, value, -prime_mover) %>%
	group_by(prime_mover, variable) %>%
	summarize(prop_missing = mean(is.na(value))) %>%
	ungroup %>%
	ggplot(aes(x = variable, y = prop_missing, fill = prime_mover, group = prime_mover)) +
	geom_col(position = 'dodge') +
	coord_flip() +
	scale_y_continuous(labels = scales::percent_format()) +
	scale_x_discrete(limits = rev) +
	theme(
		axis.ticks = element_blank()
	) +
	labs(x = 'Variable', y = 'Missing data')


# Use parallel test to see how many components the pca will use.
# Exclude real_opex; use spearman's rho rank-correlation, accounting for outliers
ParallelTests <-
	Data %>%
		select(prime_mover, all_of(variables_for_clusters)) %>%
		group_by(prime_mover) %>%
		nest %>%
		mutate(
			variables_with_variance = map(data, get_variable_names_with_variance),
			data = map2(data, variables_with_variance, select)) %>%
		expand_grid(resample_i = seq(1, 200)) %>%
		mutate(
			data = map(data, sample_frac, size = 1, replace = T),
			cor = map(data, cor, method = 's', use = 'pairwise.complete.obs'),
			n_obs = map_int(data, nrow),
			parallel_test = map2(cor, n_obs, ~fa.parallel(x = .x, n.obs = .y, plot = F, fa = 'pc')),
			num_components = map_dbl(parallel_test, 'ncomp')
		)

ParallelTests %>%
	select(prime_mover, resample_i, num_components) %>%
	count(prime_mover, num_components) %>%
	group_by(prime_mover) %>%
	mutate(
		prop = n / sum(n),
		is_modal = n == max(n)
	) %>%
	ungroup %>%
	mutate(num_components = factor(num_components)) %>%
	ggplot(aes(x = num_components, y = prop, fill = is_modal)) +
	geom_col() +
	facet_wrap(~prime_mover, ncol = 1) +
	scale_y_continuous(labels = scales::percent_format()) +
	scale_fill_manual(values = c('FALSE' = 'grey30', 'TRUE' = 'dodgerblue')) +
	theme(
		axis.ticks = element_blank()
	) +
	labs(x = 'Number of components for PCA', y = '% of parallel tests', 
			 fill = 'Is modal?',
			 caption = '200 resamples'
	)
#
NumPcaComponents <-
	ParallelTests %>%
		count(prime_mover, num_components) %>%
		group_by(prime_mover) %>%
		slice(which.max(n)) %>%
		ungroup %>%
		select(prime_mover, num_components)

NumPcaComponents %>%
	write_csv('clean_data/num_pca_components.csv')

# Fit PCA
NestedPcaMods <-
	# By using spearman's rho, we're robust to outliers. This means we have
	# to assign scores in a separate step (you can't return scores in the pca
	# fit step if you only input a correlation matrix!)
	Data %>%
		select(prime_mover, rowid, all_of(variables_for_clusters)) %>%
		group_by(prime_mover) %>%
		nest %>%
		inner_join(NumPcaComponents, by = 'prime_mover') %>%
	mutate(
			rowid = map(data, ~select(., 'rowid')),
			data = map(data, ~select(., -'rowid')),
			variables = map(data, get_variable_names_with_variance),
			data = map2(data, variables, select),
			cor = map(data, cor, method = 's', use = 'pairwise.complete.obs'),
			n_obs = map_int(data, nrow),
			pca_fit = pmap(list(r = cor, nfactors = num_components, n.obs = n_obs), 
										 pca, rotate = 'promax'),
			scores = map2(pca_fit, data, predict.psych)
		) %>%
	ungroup




# Get scores
VarianceExplainedPerComponent <-
	# note how much variance was explained by each component for each prime mover class
	NestedPcaMods %>%
		select(prime_mover, pca_fit) %>%
		mutate(
			variance_accounted = map(pca_fit, 'Vaccounted'),
			variance_accounted = map(variance_accounted, as.data.frame),
			variance_accounted = map(variance_accounted, rownames_to_column, var = 'variable')
		) %>%
		unnest(variance_accounted) %>%
		filter(variable == 'Proportion Explained') %>%
		select(-pca_fit, -variable) %>%
		gather(component, variance_explained, -prime_mover) %>%
		drop_na(variance_explained)


VarianceExplainedPerComponent %>%
	# visualize variance explained per component
	ggplot(aes(x = component, y = variance_explained)) +
	geom_col() +
	facet_wrap(~prime_mover, scales = 'free_x') +
	scale_y_continuous(labels = scales::percent_format()) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank()
	) +
	labs(x = 'Component', y = 'Variance explained')

# Scale scores; then, multiply scores by prop variance explained to 
# weight them		
WeightedScores <-
	NestedPcaMods %>%
		select(prime_mover, rowid, scores) %>%
		mutate(scores = map(scores, as.data.frame)) %>%
		unnest(c(rowid, scores)) %>%
		gather(component, score, -prime_mover, -rowid) %>%
		drop_na(component, score) %>%
		left_join(VarianceExplainedPerComponent, by = c('prime_mover', 'component')) %>%
		group_by(prime_mover, component) %>%
		mutate(
			score = as.vector(scale(score)),
			weighted_score = score * variance_explained
		) %>%
		ungroup %>%
		select(prime_mover, rowid, component, weighted_score)

WeightedScores %>%
	write_csv('clean_data/weighted_scores.csv')


NestedPcaMods %>%
	select(prime_mover, pca_fit) %>%
	write_rds(., 'clean_data/nested_pca_mods.RDS')
write_csv(VarianceExplainedPerComponent, 'clean_data/variance_explained_per_component.csv')
