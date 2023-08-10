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

setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

WeightedDataBySubplantScores <- read_csv('clean_data/weighted_data_by_subplant_scores.csv')
WeightedHistoricalDataScores <- read_csv('clean_data/weighted_historical_data_scores.csv')
WeightedEternallyPresentScores <- read_csv('clean_data/weighted_eternally_present_scores.csv')

LongVariableKey <- read_csv('clean_data/long_variable_key.csv') # for appendix EDA only
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


#### Save data to disk #### 

saveRDS(object = ClustersFit, file = 'clean_data/clusters_fit.RDS')
saveRDS(object = ClusteredHistoricalData, file = 'clean_data/clustered_historical_data.RDS')
saveRDS(object = ClusteredEternallyPresent, file = 'clean_data/clustered_eternally_present.RDS')

ClustersFit %>%
	select(rowid, cls) %>%
	unnest(everything()) %>%
	write_csv('clean_data/clustered_data_by_subplant.csv')

#### End here^ #####
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
	scale_y_continuous(labels = scales::comma_format(1)) +
	labs(x = 'Number of clusters', y = 'Total within-cluster sum of squares',
			 color = 'Clustering schemas', 
			 title = 'Chosen number of clusters') +
	theme(legend.position = 'bottom',
				axis.ticks = element_blank(),
				panel.grid.minor.x = element_blank(),
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

ClsCounts %>%
	left_join(JoinmeIsChosen) %>%
	mutate(is_chosen = replace_na(is_chosen, FALSE)) %>%
	write_csv('results/cls_counts.csv')


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
	labs(x = 'Number of clusters, per possible clustering schema', y = 'n',
			 fill = 'Clustering schemas', 
			 title = 'Size of clustering schemas',
			 caption = str_wrap('Dotted lines represent the size of each cluster that we would expect, naively, if each dataset were divided evenly; for example, a subpopulation of 100 observations, split into four clusters, would have a dotted-line at 100/4, or 25.', 100))

# Cluster characteristics
variables_for_sanity_check_cc <- c('age_in_report_year', 'capacity_mw', 
																	 'generator_starts', 'gross_cf', 'natural_gas_fraction', 'petroleum_fraction', 
																	 'minor_fuels_fraction')

variables_for_sanity_check_gt <- c('age_in_report_year', 'capacity_mw', 
																	 'generator_starts', 'gross_cf', 'natural_gas_fraction', 'petroleum_fraction',  
																	 'minor_fuels_fraction')

variables_for_sanity_check_st <- c('age_in_report_year', 'capacity_mw', 
																	 'generator_starts', 'gross_cf', 'coal_fraction', 'natural_gas_fraction', 
																	 'petroleum_fraction', 'minor_fuels_fraction')

ClustersFit %>%
	select(rowid, cls) %>%
	unnest(c(rowid, cls)) %>%
	inner_join(DataBySubplant, by = 'rowid') %>%
	filter(prime_mover == 'CC') %>%
	select(cls, all_of(variables_for_sanity_check_cc)) %>%
	group_by(cls) %>%
	nest %>%
	ungroup %>%
	mutate(Cor = map(data, cor, method = 's', use = 'pairwise.complete.obs'),
				 Cor = map(Cor, as.data.frame),
				 Cor = map(Cor, rownames_to_column, 'variable1')) %>%
	select(cls, Cor) %>%
	unnest(Cor) %>%
	gather(variable2, cor, -cls, -variable1) %>%
	# drop_na(cor) %>%
	ggplot(aes(x = variable1, y = variable2, fill = cor)) +
	geom_raster() +
	scale_y_discrete(limits = rev) +
	scale_fill_gradient2(low = 'red', mid = 'white', high = 'blue', na.value = 'grey',
											 limits = c(-1, 1)) +
	facet_wrap(~cls) +
	theme(
		axis.ticks = element_blank(),
		panel.background = element_blank(),
		text = element_text(family = 'serif'),
		legend.position = 'bottom',
		axis.text.x = element_text(angle = 90, vjust = 0.5, hjust=1)
	) +
	labs(x = '', y = '', fill = 'Spearman\'s rho', 
			 title = 'Characteristics of chosen clusters: CC: 4 Clusters',
			 caption = 'Nb these are NOT the regression variables-- rather, these are variables we chose to make sense of these clusters') 
	
AvgValue <-
	ClustersFit %>%
		select(rowid, cls) %>%
		unnest(c(rowid, cls)) %>%
		inner_join(DataBySubplant, by = 'rowid') %>%
		filter(prime_mover == 'CC') %>%
		select(cls, all_of(variables_for_sanity_check_cc)) %>%
		gather(variable, value, -cls) %>%
		group_by(variable) %>%
		summarize(avg = mean(value)) %>%
		ungroup

ClustersFit %>%
	select(rowid, cls) %>%
	unnest(c(rowid, cls)) %>%
	inner_join(DataBySubplant, by = 'rowid') %>%
	filter(prime_mover == 'GT') %>%
	select(cls, all_of(variables_for_sanity_check_cc)) %>%
	gather(variable, value, -cls) %>%
	ggplot(aes(x = ordered(cls), y = value)) +
	geom_hline(data = AvgValue, aes(yintercept = avg), linetype = 'dashed') +
	geom_boxplot(outlier.alpha = 1, varwidth = TRUE) +
	facet_wrap(~variable, scales = 'free') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		panel.grid.minor.y = element_blank(),
		text = element_text(family = 'serif'),
	) +
	labs(x = 'Cluster', y = '', 
			 title = 'Characteristics of chosen clusters: GT: 3 Clusters',
			 caption = str_wrap('Nb these are NOT the regression variables-- rather, these are variables we chose to make sense of these clusters. Horizontal line indicates overall mean value; Boxplot width represents cluster size') )

	
RowToClusterAll <-
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
		expand_grid(num_clusters = seq(2, 5)) %>%
		mutate(
			cls_fit = map2(data, num_clusters, kmeans),
			cls = map(cls_fit, 'cluster')
		) %>%
		select(prime_mover, rowid, num_clusters, cls) %>%
		unnest(c(rowid, cls))


# ClustersFit %>%
prime_mover_var <- 'ST'
num_clusters_var <- 5
variables_var <- variables_for_sanity_check_st

	# Create boxplots for each clustering schema
	my_title <- str_c(prime_mover_var, ': ', num_clusters_var, ' clusters')
	fn <- str_c('results/boxplot_', prime_mover_var, '_', num_clusters_var, '.png')
	
	AvgValue <-
		RowToClusterAll %>%
			filter(
				prime_mover == prime_mover_var,
				num_clusters == num_clusters_var
			) %>%
			inner_join(DataBySubplant, by = 'rowid') %>%
			select(cls, all_of(variables_var)) %>%
			gather(variable, value, -cls) %>%
			group_by(variable) %>%
			summarize(avg = mean(value)) %>%
			ungroup
	
	g <-	
		RowToClusterAll %>%
			filter(
				prime_mover == prime_mover_var, 
				num_clusters == num_clusters_var
			) %>%
			inner_join(DataBySubplant, by = 'rowid') %>%
			select(cls, all_of(variables_var)) %>%
			gather(variable, value, -cls) %>%
			ggplot(aes(x = ordered(cls), y = value)) +
			geom_hline(data = AvgValue, aes(yintercept = avg), linetype = 'dashed') +
			geom_boxplot(outlier.alpha = 1, varwidth = TRUE) +
			facet_wrap(~variable, scales = 'free') +
			theme(
				axis.ticks = element_blank(),
				panel.grid.major.x = element_blank(),
				text = element_text(family = 'serif'),
			) +
			labs(x = 'Cluster', y = '', title = my_title, 
					 caption = 'Horizontal line indicates overall mean value;\nBoxplot width represents cluster size')
	g
	ggsave(filename = fn, plot = g, width = 16, height = 9, units = 'in')

#
	variables_for_sanity_check_cc <- c('age_in_report_year', 'capacity_mw', 
																		 'generator_starts', 'gross_cf', 'natural_gas_fraction', 'petroleum_fraction', 
																		 'minor_fuels_fraction')


ClusteredEternallyPresent %>%
	unnest(c(rowid, cls))

ClusteredEternallyPresent %>%
	unnest(c(rowid, cls)) %>%
	inner_join(EternallyPresent %>% rowid_to_column()) %>%
	select(prime_mover, cls, all_of(variables_for_sanity_check_cc)) %>%
	gather(variable, value, -prime_mover, -cls) %>%
	ggplot(aes(x = factor(cls), y = value)) +
	geom_boxplot() +
	facet_wrap(prime_mover ~ variable, scales = 'free') 

EternallyPresent %>%
	count(prime_mover)

ClusteredEternallyPresent %>%
	unnest(cls) %>%
	count(prime_mover, cls)
