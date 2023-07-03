# Account for colinearity by fitting PCA components before the clustering
	# Note that in this script we are clustering on a subset of the regression 
	# variables (exclude real_opex);

library(tidyverse)
library(skimr)
library(psych)
library(conflicted)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

CleanedDataBySubplant <-
	read_csv('clean_data/cleaned_data_by_subplant.csv') %>%
		filter(consolidated_regression_filter)

CleanedHistoric <- read_csv('clean_data/cleaned_historical_data.csv')

LongVariableKey <- read_csv('clean_data/long_variable_key.csv', col_types = c(
	variable = 'c', .default = 'f'))

get_variables_with_variance <- function(X){
	sapply(X, var) %>%
		enframe('variable', 'variance') %>%
		filter(!is.na(variance), variance > 0) %>%
		pull(variable)
}

#### Prepare the variable key table (this step can be moved to a ETL script later) ####
core_variables <-
	LongVariableKey  %>%
		filter(variable_type == 'core') %>%
		distinct(variable) %>%
		pull

# all necessary variables present
setdiff(core_variables, colnames(CleanedDataBySubplant))

CandidateVariables <-
	LongVariableKey %>%
		filter(variable_type != 'unused') %>%
		select(prime_mover, variable) %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		rename(candidate_variables = data) %>%
		mutate(candidate_variables = map(candidate_variables, pull))

# For each prime_mover type, select ALL variables that are core OR optional
# Filter out variables without variance (unnecessary here)
NestedCleanDataBySubplant <-
	CleanedDataBySubplant %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		left_join(CandidateVariables, by = 'prime_mover') %>%
		mutate(
			rowid = map(data, select, 'rowid'),
			# Select candidate variables, and ensure they have variance
			data = map2(data, candidate_variables, ~select(.x, all_of(.y))),
			variables_with_variance = map(data, get_variables_with_variance),
			data = map2(data, variables_with_variance, ~select(.x, all_of(.y))),
		) %>%
		select(prime_mover, rowid, data)

# resample data x 100 boots
# Find number of PCA components
NestedParallelTests <-
	NestedCleanDataBySubplant %>%
		expand_grid(boot_num = seq(1, 100)) %>%
		mutate(
			data = map(data, sample_frac, size = 0.75, replace = T),
			Cor = map(data, cor, method = 's', use = 'pairwise.complete.obs'),
			n_obs = map_int(data, nrow),
			parallel_fit = map2(Cor, n_obs, fa.parallel, fa = 'pc', plot = F),
			num_components = map_dbl(parallel_fit, 'ncomp')
		)

NestedParallelTests %>%
	count(prime_mover, num_components) %>%
	ggplot(aes(x = num_components, y = n)) +
	geom_col() +
	facet_wrap(~prime_mover, ncol = 1) +
	labs(x = 'Number of components', y = 'n', title = 'Frequency with which a number of components is recommended')

# Put the outcome in a table, so we know how many PCA components per prime_mover
NumPcaComponents <-
	NestedParallelTests %>%
		count(prime_mover, num_components) %>%
		group_by(prime_mover) %>%
		slice(which.max(n)) %>%
		ungroup %>%
		select(prime_mover, num_components)
print(NumPcaComponents)

#### Fit the PCA models to the dataset ####

# Note which variables the PCA model is fit to
# (The Historical dataset will need the same columns)
VariablesToSelect <-
	NestedCleanDataBySubplant %>%
		mutate(variables = map(data, colnames)) %>%
		select(prime_mover, variables)

NestedPcaMods <-
	NestedCleanDataBySubplant %>%
		left_join(NumPcaComponents, by = 'prime_mover') %>%
		mutate(
			n_obs = map_int(data, nrow),
			Cor = map(data, cor, method = 's', use = 'pairwise.complete.obs'),
			pca_fit = pmap(list(r = Cor, nfactors = num_components, n.obs = n_obs), 
										 pca, rotate = 'promax'),
		scores = map2(pca_fit, data, predict.psych)
		) %>%
		select(prime_mover, rowid, data, pca_fit, scores)

# Apply these pca models to the Historic data to get the scores for those data.
JoinablePcaMods <-
	NestedPcaMods %>%
		select(prime_mover, pca_fit, data)

HistoricPcaScores <-
	CleanedHistoric %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		inner_join(VariablesToSelect, by = 'prime_mover') %>%
		mutate(
			rowid = map(data, select, 'rowid'),
			data = map2(data, variables, select)) %>%
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
	# note how much variance was explained by each component for each prime mover 
	# class
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
print(VarianceExplainedPerComponent)

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
print(MeansAndSds)

WeightedDataBySubplantScores <-
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
WeightedDataBySubplantScores

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

WeightedDataBySubplantScores %>%
	write_csv('clean_data/weighted_data_scores.csv')
WeightedHistScores %>%
	write_csv('clean_data/weighted_hist_scores.csv')
NumPcaComponents %>%
	write_csv('clean_data/num_pca_components.csv')
write_csv(VarianceExplainedPerComponent, 'clean_data/variance_explained_per_component.csv')

