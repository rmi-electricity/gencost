# Account for colinearity by fitting PCA components before the clustering

library(tidyverse)
library(skimr)
library(psych)
library(conflicted)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')

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

# Use parallel test to see how many components the pca will use
ParallelTests <-
	Data %>%
		select(prime_mover, all_of(variables_for_regressions)) %>%
		group_by(prime_mover) %>%
		nest %>%
		expand_grid(resample_i = seq(1, 500)) %>%
		mutate(
			data = map(data, sample_frac, replace = T, size = 1),
			variables = map(data, get_variable_names_with_variance),
			data = map2(data, variables, select),
			cor_matrix = map(data, cor, use = 'pairwise.complete.obs', method = 'p'),
			num_obs = map_int(data, nrow),
			parallel_test = map2(cor_matrix, num_obs, ~fa.parallel(
				x = .x, n.obs = .y, fa = 'pc', plot = F)),
			num_components = map_dbl(parallel_test, 'ncomp'),
	)

ParallelTests %>%
	select(prime_mover, resample_i, num_components) %>%
	count(prime_mover, num_components) %>%
	group_by(prime_mover) %>%
	mutate(
		is_modal = n == max(n),
		prop = n/sum(n)
	) %>%
	ungroup %>%
	ggplot(aes(x = num_components, y = prop, fill = is_modal)) +
	geom_col() +
	facet_wrap(~prime_mover, ncol = 1) +
	scale_fill_manual(values = c('FALSE' = 'grey30', 'TRUE' = 'dodgerblue')) +
	scale_y_continuous(labels = scales::percent_format()) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		legend.position = 'none'
	) +
	labs(x = 'Number of components', y = '', title = 'Recommended number of PCA components')

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
	Data %>%
		select(prime_mover, rowid, all_of(variables_for_regressions)) %>%
		group_by(prime_mover) %>%
		nest %>%
		inner_join(NumPcaComponents, by = 'prime_mover') %>%
		mutate(
			rowid = map(data, ~select(., 'rowid')),
			data = map(data, ~select(., -'rowid')),
			variables = map(data, get_variable_names_with_variance),
			data = map2(data, variables, select),
			pca_fit = map2(data, num_components, ~pca(
				r = .x, nfactors = .y, rotate = 'promax', use = 'pairwise.complete.obs',
				scores = TRUE, missing = T, impute = 'median')),
		) %>%
	ungroup

# Get scores

VarianceExplainedPerComponent <-
	# note how much variance was explained by each component for each prime mover class
	NestedPcaMods %>%
		mutate(
			# scores = map(pca_fit, 'scores'),
			# scores = map(scores, as.data.frame),
			variance_accounted = map(pca_fit, 'Vaccounted'),
			variance_accounted = map(variance_accounted, as.data.frame),
			variance_accounted = map(variance_accounted, rownames_to_column, var = 'variable'),
					 ) %>%
		select(-data, -num_components, -variables, -pca_fit, -rowid) %>%
		unnest(variance_accounted) %>%
		filter(variable == 'Proportion Explained') %>%
		select(-variable) %>%
		gather(component, variance_explained, -prime_mover) %>%
		drop_na

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

Scores <-
	NestedPcaMods %>%
		mutate(
			scores = map(pca_fit, 'scores'),
			scores = map(scores, as.data.frame),
					 ) %>%
		select(-data, -num_components, -variables, -pca_fit) %>%
		unnest(c(rowid, scores)) %>%
		gather(component, score, -rowid, -prime_mover) %>%
		drop_na(score)

# Scale scores; then, multiply scores by prop variance explained to 
# weight them		
WeightedScores <-
	Scores %>%
		group_by(prime_mover, component) %>%
		mutate(score = as.vector(scale(score))) %>%
		ungroup %>%
		inner_join(VarianceExplainedPerComponent, by = c('prime_mover', 'component')) %>%
		mutate(weighted_score = score * variance_explained) %>%
		select(rowid, prime_mover, component, weighted_score)

WeightedScores %>%
	write_csv('clean_data/weighted_scores.csv')
