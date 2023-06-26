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

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

Data <- read_csv('clean_data/data.csv', col_types = c(
	prime_mover = 'c', plant_id_eia = 'f', 
	consolidated_regression_filter = 'l', .default = 'd')) %>%
	filter(consolidated_regression_filter)

Historic <- read_csv('clean_data/historic_for_clustering.csv', col_types = c(
	prime_mover = 'c', plant_id_eia = 'f',  .default = 'd'))

variables_for_regressions <- readRDS('clean_data/variables_for_regressions.RDS')
variables_for_clusters <- readRDS('clean_data/variables_for_clusters.RDS')
get_variable_names_with_variance <- readRDS('clean_Data/get_variable_names_with_variance.RDS')

#### Find number of components necessary for the PCA ####
# Use parallel test to see how many components the pca will use.
# Break out the data by prime mover; resample data with replacement, 
# and run the test x200 (takes a few moments)
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

# Plot findings
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

# Put the outcome in a table, so we know how many PCA components per prime_mover
NumPcaComponents <-
	ParallelTests %>%
		count(prime_mover, num_components) %>%
		group_by(prime_mover) %>%
		slice(which.max(n)) %>%
		ungroup %>%
		select(prime_mover, num_components)

# Fit PCA

# Note the variables that exist in the historic data, the fitted data, and the variables
# we want for our clustering!
# common_variables <- intersect(colnames(Data), colnames(Historic))
# common_variables_and_clusters <- intersect(common_variables, variables_for_clusters)
# all(variables_for_clusters %in% common_variables_and_clusters)
# variables_to_select <- c('rowid', 'prime_mover', common_variables_and_clusters)

# NEED:
# prime mover
# rowid
# variables for clusters
# ...that have variance


VariablesToSelect <-
	bind_rows(
		mutate(Data, data_type = 'Data'),
		mutate(Historic, data_type = 'Historic')
	) %>%
	group_by(data_type, prime_mover) %>%
		nest %>%
		ungroup %>%
		mutate(
			variables_with_variance = map(data, get_variable_names_with_variance),
		) %>%
		select(-data) %>%
		spread(data_type, variables_with_variance) %>%
		rename(variables_with_variance_data = Data, variables_with_variance_historic = Historic) %>%
		mutate(
			common_variables_with_variance = map2(
				variables_with_variance_data, 
				variables_with_variance_historic, 
				intersect
			),
			variables_to_select = map(common_variables_with_variance, 
																~intersect(., variables_for_clusters)
			)
		) %>%
		select(prime_mover, variables_to_select)

# Now that we know which variables we can fit the PCA models to, fit them on the
# Data table.
# By using spearman's rho, we're robust to outliers. This means we have
# to assign scores in a separate step (you can't return scores in the pca
# fit step if you only input a correlation matrix!)
NestedPcaMods <-
	Data %>%
	group_by(prime_mover) %>%
	nest %>%
	ungroup %>%
	left_join(VariablesToSelect, by = 'prime_mover') %>%
	mutate(
		rowid = map(data, ~select(., 'rowid')),
		data = map2(data, variables_to_select, select)
	) %>%
	left_join(NumPcaComponents, by = 'prime_mover') %>%
	select(prime_mover, rowid, data, num_components) %>%
	mutate(
		cor = map(data, cor, method = 's', use = 'pairwise.complete.obs'),
		n_obs = map_int(data, nrow),
		pca_fit = pmap(list(r = cor, nfactors = num_components, n.obs = n_obs), 
									 pca, rotate = 'promax'),
		scores = map2(pca_fit, data, predict.psych)
	)

# Apply these pca models to the Historic data to get the scores for those data.
JoinablePcaMods <-
	NestedPcaMods %>%
		select(prime_mover, pca_fit, data)

HistoricPcaScores <-
	Historic %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		left_join(VariablesToSelect, by = 'prime_mover') %>%
		mutate(
			rowid = map(data, select, 'rowid'),
			data = map2(data, variables_to_select, select)) %>%
		select(prime_mover, rowid, new_data = data) %>%
		left_join(JoinablePcaMods, by = 'prime_mover') %>%
		mutate(
			scores = pmap(
				list(object = pca_fit, data = new_data, old.data = data), 
				predict.psych
			)
		) %>%
		select(prime_mover, rowid, scores)
	
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

# Scale the Data scores, multiply by variance explained per component
# Note the mean and sd for each component!
MeansAndSds <-
	NestedPcaMods %>%
		select(prime_mover, scores) %>%
		mutate(scores = map(scores, as.data.frame)) %>%
		unnest(scores) %>%
		gather(component, score, -prime_mover) %>%
		drop_na(score) %>%
		group_by(prime_mover, component) %>%
		summarize(mean = mean(score), sd = sd(score)) %>%
		ungroup

WeightedDataScores <-
	NestedPcaMods %>%
		select(prime_mover, rowid, scores) %>%
		mutate(scores = map(scores, as.data.frame)) %>%
		unnest(c(rowid, scores)) %>%
		gather(component, score, -prime_mover, -rowid) %>%
		group_by(prime_mover, component) %>%
		mutate(scaled_score = as.vector(scale(score))) %>%
		ungroup %>%
		left_join(VarianceExplainedPerComponent, by = c('prime_mover', 'component')) %>%
		mutate(weighted_scaled_score = variance_explained * scaled_score) %>%
		select(prime_mover, rowid, component, weighted_scaled_score) %>%
		spread(component, weighted_scaled_score)

# Scale the Historic data according to Data mean and sd; weight acc'd to variance
# explained per PCA component
WeightedHistScores <-
	HistoricPcaScores %>%
		mutate(scores = map(scores, as.data.frame)) %>%
		unnest(c(rowid, scores)) %>%
		gather(component, score, -prime_mover, -rowid) %>%
		left_join(MeansAndSds, by = c('prime_mover', 'component')) %>%
		mutate(scaled_score = (score - mean)/ sd) %>%
		left_join(VarianceExplainedPerComponent, by = c('prime_mover', 'component')) %>%
		mutate(weighted_scaled_score = variance_explained * scaled_score) %>%
		select(prime_mover, component, rowid, weighted_scaled_score) %>%
		spread(component, weighted_scaled_score)

WeightedDataScores %>%
	write_csv('clean_data/weighted_data_scores.csv')
WeightedHistScores %>%
	write_csv('clean_data/weighted_hist_scores.csv')

NumPcaComponents %>%
	write_csv('clean_data/num_pca_components.csv')

# NestedPcaMods %>%
# 	select(prime_mover, pca_fit) %>%
# 	write_rds(., 'clean_data/nested_pca_mods.RDS')
write_csv(VarianceExplainedPerComponent, 'clean_data/variance_explained_per_component.csv')

