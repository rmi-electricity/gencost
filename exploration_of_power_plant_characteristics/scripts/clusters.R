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
WeightedEternallyPresentScores <- read_csv('clean_data/weighted_eternally_present_scores.csv')

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

#### Assign the EP, historical data to classes ####
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

ClusteredHistoricalData <- get_clustered_data(WeightedHistoricalDataScores)
ClusteredEternallyPresent <- get_clustered_data(WeightedEternallyPresentScores)

# ClusteredHistoricalData <-
# 	WeightedHistoricalDataScores %>%
# 			group_by(prime_mover) %>%
# 			nest %>%
# 			ungroup %>%
# 			mutate(
# 				rowid = map(data, select, 'rowid'),
# 				data = map(data, select, -'rowid'),
# 				variables = map(data, get_variables_with_variance),
# 				data = map2(data, variables, select)
# 			) %>%
# 			select(prime_mover, rowid, data) %>%
# 			left_join(NestedCls, by = 'prime_mover') %>%
# 			mutate(cls = map2(cls_fit_flexclust, data, predict)) %>%
# 			select(prime_mover, cls)

saveRDS(object = ClustersFit, file = 'clean_data/clusters_fit.RDS')
saveRDS(object = ClusteredHistoricalData, file = 'clean_data/clustered_historical_data.RDS')
saveRDS(object = ClusteredEternallyPresent, file = 'clean_data/clustered_eternally_present.RDS')

ClustersFit %>%
	select(rowid, cls) %>%
	unnest(everything()) %>%
	write_csv('clean_data/clustered_data_by_subplant.csv')

# End here #
# GOF for competing models

ResampledClustering <-
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
		expand_grid(resample_num = seq(1, 10)) %>%
		mutate(data = map(data, sample_frac, size = 1, replace = T)) %>%
		expand_grid(num_clusters = seq(2, 5)) %>%
		mutate(
			cls_fit = map2(data, num_clusters, kmeans),
			cls = map(cls_fit, 'cluster'),
			tot_withinss = map_dbl(cls_fit, 'tot.withinss')
		)

JoinmeIsChosen <-
	NumClusters %>%
		mutate(is_chosen = TRUE)

ResampledClustering	%>%
	select(prime_mover, resample_num, num_clusters, tot_withinss) %>%
	left_join(JoinmeIsChosen, by = c('prime_mover', 'num_clusters')) %>%
	mutate(
		is_chosen = replace_na(is_chosen, FALSE),
		label_text = if_else(is_chosen, 'Chosen', 'Discarded')
	) %>%
	ggplot(aes(x = num_clusters, y = tot_withinss)) +
	geom_smooth(method = 'lm', formula = y ~ poly(x, 2), se = T, color = 'grey50') +
	geom_point(aes(color = label_text)) +
	facet_wrap(~prime_mover) +
	scale_color_manual(values = c('Discarded' = 'grey20', 'Chosen' = 'dodgerblue')) +
	labs(x = 'Number of clusters', y = 'Total within-cluster sum of squares',
			 color = 'Clustering schemas', 
			 title = 'Chosen number of clusters') +
	theme(legend.position = 'bottom',
				axis.ticks = element_blank(),
				text = element_text(family = 'serif'))

# Histograms for competing models

ClsCounts <-
	WeightedDataBySubplantScores %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		mutate(
			# rowid = map(data, select, 'rowid'),
			data = map(data, select, -'rowid'),
			variables = map(data, get_variables_with_variance),
			data = map2(data, variables, select)
		) %>%
		select(prime_mover, data) %>%
		expand_grid(num_clusters = seq(2, 5)) %>%
		mutate(
			cls_fit = map2(data, num_clusters, kmeans),
			cls = map(cls_fit, 'cluster'),
		) %>%
		select(prime_mover, num_clusters, cls) %>%
		unnest(cls) %>%
		count(prime_mover, num_clusters, cls) %>%
		group_by(prime_mover, num_clusters) %>%
		mutate(prop = n / sum(n),
					 prop = round(prop, 2)
	  ) %>%
		ungroup
write_csv(ClsCounts, 'results/cls_counts.csv')

EvenSplitSize <-
	ClsCounts	%>%
		group_by(prime_mover, num_clusters) %>%
		summarize(total = sum(n)) %>%
		ungroup %>%
		mutate(even_split = total / num_clusters)

ClsCounts	%>%
	left_join(JoinmeIsChosen) %>%
	mutate(
		is_chosen = replace_na(is_chosen, FALSE),
		label_text = if_else(is_chosen, 'Chosen', 'Discarded')
	) %>%
	ggplot(aes(x = ordered(cls), y = n)) +
	geom_hline(data = EvenSplitSize, aes(yintercept = even_split), linetype = 'dashed') +
	geom_col(aes(fill = label_text)) +
	scale_fill_manual(values = c('Discarded' = 'grey20', 'Chosen' = 'dodgerblue')) +
	facet_wrap(prime_mover ~ num_clusters, scales = 'free') +
	theme(
		axis.ticks = element_blank(),
		text = element_text(family = 'serif'),
		panel.grid.major.x = element_blank(),
		legend.position = 'bottom'
	) +
	labs(x = 'Number of clusters', y = 'n',
			 fill = 'Clustering schemas', 
			 title = 'Size of clustering schemas',
			 caption = str_wrap('Dotted lines represent the size of each cluster that we would expect, naively, if each dataset were divided evenly; for example, a subpopulation of 100 observations, split into four clusters, would have a dotted-line at 100/4, or 25.', 100))


