# let's go with 3 for STs and GTs, and 4 for CCs

library(tidyverse)
library(skimr)
# library(psych)
library(conflicted)
library(flexclust)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

#### Load data ####
# CleanedDataBySubplant <- read_csv('clean_data/cleaned_data_by_subplant_data.csv')
# CleanedHistoricalData <- read_csv('clean_data/cleaned_historical_data.csv')

WeightedDataBySubplantScores <- read_csv('clean_data/weighted_data_by_subplant_scores.csv')
WeightedHistoricalDataScores <- read_csv('clean_data/weighted_historical_data_scores.csv')

#### Define functions ####
get_variables_with_variance <- function(X){
	sapply(X, var) %>%
		enframe('variable', 'variance') %>%
		filter(!is.na(variance), variance > 0) %>%
		pull(variable)
}


#### Define datasets ####
NumClusters <- tribble(
# 3 for STs and GTs, and 4 for CCs
	~prime_mover, ~num_clusters,
	'CC', 4L,
	'GT', 3L,
	'ST', 3L
)

#### Fit the DataBySubplant data with our desired number of clusters ####
# Convert the model to the kcca class as well, because this can 'predict'
# the classes of new data (eg Historical)

ClustersFit <-
	WeightedDataBySubplantScores %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		mutate(
			rowid = map(data, select, 'rowid'),
			data = map(data, select, -'rowid'),
			variables = map(data, get_variables_with_variance),
			data = map2(data, variables, select)
		) %>%
		select(prime_mover, rowid, data) %>%
		left_join(NumClusters, by = 'prime_mover') %>%
		mutate(
			cls_fit = map2(data, num_clusters, kmeans),
			cls_fit_flexclust = map2(cls_fit, data, as.kcca),
			cls = map(cls_fit, 'cluster')
		)

#### Assign the historical data to classes ####
NestedCls <-
	ClustersFit %>%
		select(prime_mover, cls_fit_flexclust)

ClusteredHistoricalData <-
	WeightedHistoricalDataScores %>%
			group_by(prime_mover) %>%
			nest %>%
			ungroup %>%
			mutate(
				rowid = map(data, select, 'rowid'),
				data = map(data, select, -'rowid'),
				variables = map(data, get_variables_with_variance),
				data = map2(data, variables, select)
			) %>%
			select(prime_mover, rowid, data) %>%
			left_join(NestedCls, by = 'prime_mover') %>%
			mutate(cls = map2(cls_fit_flexclust, data, predict)) %>%
			select(prime_mover, cls)

saveRDS(object = ClustersFit, file = 'clean_data/clusters_fit.RDS')
saveRDS(object = ClusteredHistoricalData, file = 'clean_data/clustered_historical_data.RDS')

# End here #