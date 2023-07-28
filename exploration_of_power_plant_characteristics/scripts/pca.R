# GenCost workflow
# 2. PCA
# Andrew Bartnof, for RMI, 2023
# abartnof.contractor@rmi.org

# We want to fit a clustering model on these data, but first, we have to
# account for colinearity in the data. If we represent these data
# with PCA models, then we don't have the same issue. 
# In order to decide how many components we'll use, we'll resample the data
# and apply parallel tests (psych package), and see, in general, if these
# parallel tests tend to agree on how many components would be parsimoneous.
# Also note that we'll scale the PCA scores before clustering; use the 
# DataBySubplant PCA score mean and sd in order to scale the EternallyPresent
# and HistoricalData PCA scores, so that our clustering models are all 
# fit to the same data

#### Import packages ####
library(tidyverse)
library(skimr)
library(psych)
library(conflicted)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')
set.seed(1)	


#### Load local data ####
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

CleanedDataBySubplant <- read_csv('clean_data/cleaned_data_by_subplant_data.csv',
																	col_types = c('prime_mover' = 'c', 'rowid' = 'i',
																	.default = 'd'))
CleanedHistoricalData <- read_csv('clean_data/cleaned_historical_data.csv',
																	col_types = c('prime_mover' = 'c', 'rowid' = 'i',
																	.default = 'd'))
CleanedEternallyPresent <- read_csv('clean_data/cleaned_eternally_present.csv',
																	col_types = c('prime_mover' = 'c', 'rowid' = 'i',
																	.default = 'd'))

LongVariableKey <- read_csv('clean_data/long_variable_key.csv', col_types = c(
	variable = 'c', .default = 'f'))

#### Define functions #### 
get_variables_with_variance <- function(X){
	sapply(X, var) %>%
		enframe('variable', 'variance') %>%
		filter(!is.na(variance), variance > 0) %>%
		pull(variable)
}

####  Ensure that all variables are present in the datasets ####
core_variables <-
	LongVariableKey  %>%
		filter(variable_type == 'core') %>%
		distinct(variable) %>%
		pull

# all necessary variables present
setdiff(core_variables, colnames(CleanedDataBySubplant))

# For each prime_mover type, select ALL variables that are core and/or optional
CandidateVariables <-
	LongVariableKey %>%
		filter(variable_type != 'unused') %>%
		select(prime_mover, variable) %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		rename(candidate_variables = data) %>%
		mutate(candidate_variables = map(candidate_variables, pull))

NestedCandidateDataBySubplant <-
	CleanedDataBySubplant %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		left_join(CandidateVariables, by = 'prime_mover') %>%
		mutate(
			rowid = map(data, select, 'rowid'),
			data = map(data, select, -'rowid'),
			data = map2(data, candidate_variables, ~select(.x, all_of(.y))),
		) %>%
		select(prime_mover, rowid, data)

#### Resample data to find number of PCA components ####
NestedParallelTests <-
	NestedCandidateDataBySubplant %>%
		expand_grid(boot_num = seq(1, 100)) %>%
		mutate(
			data = map(data, sample_frac, size = 0.75, replace = T),
			Cor = map(data, cor, method = 's', use = 'pairwise.complete.obs'),
			n_obs = map_int(data, nrow),
			parallel_fit = map2(Cor, n_obs, fa.parallel, fa = 'pc', plot = F),
			num_components = map_dbl(parallel_fit, 'ncomp')
		)

# Visualize
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

# Note which variables the extant PCA model is fit to
# (The Historical and EP datasets will need the same columns)
VariablesToSelect <-
	NestedCandidateDataBySubplant %>%
		mutate(variables = map(data, colnames)) %>%
		select(prime_mover, variables)

# Fit the mods (previous fitting was based on resampling)
NestedPcaMods <-
	NestedCandidateDataBySubplant %>%
		left_join(NumPcaComponents, by = 'prime_mover') %>%
		mutate(
			n_obs = map_int(data, nrow),
			Cor = map(data, cor, method = 's', use = 'pairwise.complete.obs'),
			pca_fit = pmap(list(r = Cor, nfactors = num_components, n.obs = n_obs), 
										 pca, rotate = 'promax'),
		# scores = map2(pca_fit, data, predict.psych)
		) %>%
		select(prime_mover, rowid, data, pca_fit)  # removed: scores

# Apply these pca models to the EP and Historic data to get the 
# scores for those data.
JoinablePcaMods <-
	NestedPcaMods %>%
		select(prime_mover, pca_fit, data)

get_pca_scores <- function(X){
	# X is either CleanedHistoricalData or CleanedEternallyPresent
	X %>%
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
}
HistoricalDataPcaScores <- get_pca_scores(CleanedHistoricalData)
EternallyPresentPcaScores <- get_pca_scores(CleanedEternallyPresent)

	
#### Get scores ####
	# note how much variance was explained by each component for each prime mover 
	# class
VarianceExplainedPerComponent <-
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

# sanity check!
VarianceExplainedPerComponent %>% 
	group_by(prime_mover) %>%
	summarize(sum(variance_explained))

# Scale the Data scores, multiply by variance explained per component
# Note the mean and sd for each component!
MeansAndSds <-
	NestedPcaMods %>%
		mutate(
			scores = map2(pca_fit, data, psych::predict.psych),
			scores = map(scores, as.data.frame)
		) %>%
		select(prime_mover, scores) %>%
		unnest(scores) %>%
		gather(component, score, -prime_mover) %>%
		drop_na(score) %>%
		group_by(prime_mover, component) %>%
		summarize(mean = mean(score), sd = sd(score)) %>%
		ungroup
print(MeansAndSds)

WeightedDataBySubplantScores <-
	NestedPcaMods %>%
		mutate(
			scores = map2(pca_fit, data, psych::predict.psych),
			scores = map(scores, as.data.frame),
		) %>%
		select(prime_mover, rowid, scores) %>%
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

# Scale the historical and EP data according to Data mean and sd; 
# weight acc'd to variance explained per PCA component
get_weighted_scores <- function(X){
	# X is HistoricalDataPcaScores or EternallyPresentPcaScores 
		X %>%
		mutate(scores = map(scores, as.data.frame)) %>%
		unnest(c(rowid, scores)) %>%
		gather(component, score, -prime_mover, -rowid) %>%
		left_join(MeansAndSds, by = c('prime_mover', 'component')) %>%
		mutate(scaled_score = (score - mean)/ sd) %>%
		left_join(VarianceExplainedPerComponent, by = c('prime_mover', 'component')) %>%
		mutate(weighted_scaled_score = variance_explained * scaled_score) %>%
		select(prime_mover, component, rowid, weighted_scaled_score) %>%
		spread(component, weighted_scaled_score)
}

WeightedHistoricalDataScores <- get_weighted_scores(HistoricalDataPcaScores)
WeightedEternallyPresentScores <- get_weighted_scores(EternallyPresentPcaScores)

WeightedDataBySubplantScores %>%
	write_csv('clean_data/weighted_data_by_subplant_scores.csv')
WeightedHistoricalDataScores %>%
	write_csv('clean_data/weighted_historical_data_scores.csv')
WeightedEternallyPresentScores %>%
	write_csv('clean_data/weighted_eternally_present_scores.csv')
