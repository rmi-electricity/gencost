library(tidyverse)
library(skimr)
library(psych)
library(conflicted)
library(GGally)
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
	consolidated_regression_filter = 'l', .default = 'd')) %>%
	filter(consolidated_regression_filter)  # regressions will be on filtered data.
variables_for_regressions <- readRDS('clean_data/variables_for_regressions.RDS')

# Test to see how well each cluster model fits
KmeansComparisons <-
	WeightedScores %>%
		spread(component, weighted_score) %>%
		select(-rowid) %>%
		group_by(prime_mover) %>%
		nest %>%
		expand_grid(
			resample_i = seq(1, 10),
			num_clusters = seq(2, 10)
		) %>%
		mutate(
			data = map(data, sample_frac, size = 1, replace = TRUE),
			variables = map(data, get_variable_names_with_variance),
			data = map2(data, variables, select),
			kmeans_mod = map2(data, num_clusters, kmeans, 
												algorithm='MacQueen', iter.max = 100),
			tss = map_dbl(kmeans_mod, 'totss'),
			twss = map_dbl(kmeans_mod, 'tot.withinss'),
			success_ratio = twss/tss
		)
	
PairwiseTTests <-	
	KmeansComparisons	%>%
		select(prime_mover, num_clusters, success_ratio) %>%
		group_by(prime_mover) %>%
		nest %>%
		mutate(
			pairwise_t_test = map(data, ~with(., pairwise.t.test(
				x = success_ratio, g = num_clusters, 
				paired = TRUE, p.adjust.method = 'bonferroni'))),
			p_matrix = map(pairwise_t_test, 'p.value'),
			p_matrix = map(p_matrix, as.data.frame),
			p_matrix = map(p_matrix, rownames_to_column, var = 'target'),
			p_matrix = map(p_matrix, as_tibble)
		) %>%
		select(prime_mover, p_matrix) %>%
		unnest(p_matrix) %>%
		gather(reference, p, -prime_mover, -target) %>%
		mutate_at(c('target', 'reference'), parse_integer) %>%
		filter(target - 1L == reference) %>%
		ungroup %>%
		mutate(
			is_sig = p < 0.05,
			sig_label = if_else(is_sig, '*', NA_character_)
		)
PairwiseTTests %>%
	arrange(prime_mover, target)

KmeansComparisons	%>%
	select(prime_mover, resample_i, num_clusters, tss, twss, success_ratio) %>%
	ggplot(aes(x = num_clusters, y = success_ratio)) +
	geom_smooth(formula = y ~ poly(x, 2), method = 'lm', se = F) +
	geom_jitter(width = 0.1, height = 0, alpha = 0.5) +
	geom_text(data = PairwiseTTests, y = 0.95, aes(x = target, label = sig_label)) +
	coord_cartesian(ylim = c(0, 1)) +
	scale_x_continuous(breaks = seq(1, 100, by = 1)) +
	facet_wrap(~prime_mover, ncol = 3) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.minor.x = element_blank()
		) +
	labs(x = 'Number of clusters', y = 'total within SS / total SS')


	# Count how many rows are in each cluster, to make sure we don't have wildly
	# unbalanced models
Clusters <-
	WeightedScores %>%
	spread(component, weighted_score) %>%
	group_by(prime_mover) %>%
	nest %>%
	expand_grid(num_clusters = seq(2, 5)) %>%
	mutate(
		rowid = map(data, select, 'rowid'),
		data = map(data, select, -'rowid'),
		variables = map(data, get_variable_names_with_variance),
		data = map2(data, variables, select),
		kmeans_mod = map2(data, num_clusters, kmeans),
		cluster = map(kmeans_mod, 'cluster')
	)
	
SizeOfClusters <-
	Clusters %>%
	select(prime_mover, num_clusters, cluster) %>%
	unnest(cluster) %>%
	count(prime_mover, num_clusters, cluster) %>%
	group_by(prime_mover, num_clusters) %>%
	mutate(
		num_rows = sum(n),
		num_rows_evenly_split = num_rows / num_clusters,
  ) %>%
	ungroup 

SizeOfClusters %>%
	filter(prime_mover == 'CC') %>%
	mutate(cluster = as.factor(cluster)) %>%
	ggplot(aes(x = cluster, y = n)) +
	geom_hline(aes(yintercept = num_rows_evenly_split), linetype = 'dashed') +
	geom_col() +
	facet_wrap(~num_clusters, nrow = 1, scales = 'free_x') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank()
	) +
	labs(x = 'Clusters', y = 'Number of observations', title = 'CC')

SizeOfClusters %>%
	filter(prime_mover == 'GT') %>%
	mutate(cluster = as.factor(cluster)) %>%
	ggplot(aes(x = cluster, y = n)) +
	geom_hline(aes(yintercept = num_rows_evenly_split), linetype = 'dashed') +
	geom_col() +
	scale_y_continuous(labels = scales::comma_format()) +
	facet_wrap(~num_clusters, nrow = 1, scales = 'free_x') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank()
	) +
	labs(x = 'Clusters', y = 'Number of observations', title = 'GT')

SizeOfClusters %>%
	filter(prime_mover == 'ST') %>%
	mutate(cluster = as.factor(cluster)) %>%
	ggplot(aes(x = cluster, y = n)) +
	geom_hline(aes(yintercept = num_rows_evenly_split), linetype = 'dashed') +
	geom_col() +
	scale_y_continuous(labels = scales::comma_format()) +
	facet_wrap(~num_clusters, nrow = 1, scales = 'free_x') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank()
	) +
	labs(x = 'Clusters', y = 'Number of observations', title = 'ST')

# Look at the cluster-level characteristics
variables_for_sanity_check <- c('gross_cf', 'generator_starts', 'capacity_mw',
																'age_relative_to_prime_avg')

custom_smooth <- function(data, mapping, ...) {
	p <- ggplot(data = data, mapping = mapping) +
		geom_smooth(method = "lm", ...)
}
custom_hist <- function(data, mapping, ...) {
	p <- ggplot(data = data, mapping = mapping) +
		geom_histogram(alpha = 0.3, aes(y=..count../sum(..count..)))
}

show_cluster_splot <- function(prime_mover_var, num_clusters_var) {
	# Show a scatterplot matrix of the cluster characteristics given whatever
	# prime mover and number of clusters
	Clusters %>%
		select(rowid, num_clusters, cluster) %>%
		unnest(c(rowid, cluster)) %>%
		left_join(Data, by = c('rowid')) %>%
		select(prime_mover, num_clusters, cluster, real_opex, all_of(variables_for_sanity_check)) %>%
		filter(prime_mover == prime_mover_var, num_clusters == num_clusters_var) %>%
		select(cluster, real_opex, gross_cf, generator_starts) %>%
		mutate_at(c('real_opex', 'gross_cf', 'generator_starts'), ~as.vector(scale(.))) %>%
		mutate_at('cluster', factor) %>%
		ggpairs(., columns = c(2,3, 4), 
						ggplot2::aes(color = cluster,
												 fill = cluster),
			diag = list(continuous = custom_hist),
			lower = list(continuous = custom_smooth),
			upper = list(continuous =
									 	wrap('cor', use = 'pairwise.complete.obs', digits = 1))) +
		theme(
			axis.ticks = element_blank()
		) +
		labs(title = str_c(prime_mover_var, num_clusters_var, sep = ' '))
}

show_cluster_splot(prime_mover_var = 'ST', num_clusters_var = 3)												 	
	
write_csv(PairwiseTTests, file = 'clean_data/pairwise_ttests.csv')
write_csv(Clusters, file = 'clean_data/clusters.csv')

# for now, let's say we're using this number of clusters:
NumClusters <-
	tribble(
		~prime_mover, ~num_clusters,
		'CC', 3,
		'GT', 3,
		'ST', 3	
	)

ClusteredData <-
	Clusters %>%
		semi_join(NumClusters, by = c('num_clusters', 'prime_mover')) %>%
		select(rowid, cluster) %>%
		unnest(c(rowid, cluster)) %>%
		full_join(Data, by = 'rowid')
write_csv(ClusteredData, 'clean_data/clustered_data.csv')