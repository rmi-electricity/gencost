# GenCost workflow
# 3. Clusters
# Andrew Bartnof, for RMI, 2023

# Fit the PCA-scored data, broken down by prime_mover, with clusters.
# Previously, this script was more of an EDA of what would happen with
# different numbers of clusters; it has been streamlined to use
# 3 clusters for STs and GTs, and 4 for CCs


#### Import libraries ####

library(tidyverse)
library(skimr)
library(conflicted)
library(flexclust)
library(arrow)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')
conflicted::conflict_prefer('all_of', 'dplyr')
set.seed(1)	

#### Load data ####

setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/module/')

WeightedDataBySubplantScores <- read_csv('weighted_data_by_subplant_scores.csv')
WeightedNewDataScores <- read_csv('weighted_new_data_scores.csv')

#LongVariableKey <- read_csv('clean_data/long_variable_key.csv') # for appendix EDA only
DataBySubplant <- read_parquet('input_data/data_by_subplant.parquet') %>%
	rowid_to_column()

#### Define functions ####
get_variables_with_variance <- function(X){
	sapply(X, var) %>%
		enframe('variable', 'variance') %>%
		filter(!is.na(variance), variance > 0) %>%
		pull(variable)
}


#### Define datasets ####
# Note: we decided on this, this isn't the result of an automated process.
NumClusters <- tribble(
	# 3 for STs and GTs, and 4 for CCs
	~prime_mover, ~num_clusters,
	# 'CC', 3L,
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
		cls_fit = map2(data, num_clusters, kmeans, iter.max=500),
		cls_fit_flexclust = map2(cls_fit, data, as.kcca),
		cls = map(cls_fit, 'cluster')
	)

#### Assign classes to the NewData ####
NestedCls <-
	ClustersFit %>%
	select(prime_mover, cls_fit_flexclust)

get_clustered_data <- function(X){
	# input WeightedHistoricalDataScores or WeightedEternallyPresentScores
	X %>%
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
		select(prime_mover, rowid, cls)
}

ClusteredNewData <- get_clustered_data(WeightedNewDataScores)


#### Save data to disk #### 

saveRDS(object = ClustersFit, file = 'clusters_fit.RDS')
saveRDS(object = ClusteredNewData, file = 'clustered_new_data.RDS')

ClustersFit %>%
	select(rowid, cls) %>%
	unnest(everything()) %>%
	write_csv('clustered_data_by_subplant.csv')
