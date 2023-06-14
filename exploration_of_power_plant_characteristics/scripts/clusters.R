library(tidyverse)
library(skimr)
library(psych)
library(conflicted)
library(GGally)
library(ggrepel)
library(flexclust)
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

WeightedScores <- read_csv('clean_data/weighted_scores.csv')

variables_for_regressions <- readRDS('clean_data/variables_for_regressions.RDS')
variables_for_clusters <- readRDS('clean_data/variables_for_clusters.RDS')
variables_for_sanity_check_cc <- readRDS('clean_data/variables_for_sanity_check_cc.RDS')
variables_for_sanity_check_gt <- readRDS('clean_data/variables_for_sanity_check_gt.RDS')
variables_for_sanity_check_st <- readRDS('clean_data/variables_for_sanity_check_st.RDS')

VariablesForSanityCheck <-
	tribble(
		~prime_mover, ~variable,
		'CC', variables_for_sanity_check_cc,
		'GT', variables_for_sanity_check_gt,
		'ST', variables_for_sanity_check_st,
	) %>%
		unnest(variable)
#



# Test to see how well each cluster model fits
KmeansComparisons <-
	WeightedScores %>%
		spread(component, weighted_score) %>%
		select(-rowid) %>%
		group_by(prime_mover) %>%
		nest %>%
		expand_grid(
			resample_i = seq(1, 200),
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
		panel.grid.minor.x = element_blank(),
		text = element_text(family = 'serif')
		) +
	labs(x = 'Number of clusters', y = 'Total within-cluster SS / total SS',
			 caption = '200 resamples; pairwise t-tests with Bonferroni correction')


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
		# kmeans_mod = map2(data, num_clusters, 
											# ~kcca(x = .x, k = .y, kccaFamily('kmeans'))),
			# kcca(dat[dat[["train"]]==TRUE, 1:2], k=4, kccaFamily("kmeans"))
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
	geom_col(fill = '#20A2E3') +
	facet_wrap(~num_clusters, nrow = 1, scales = 'free_x') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = 'Clusters', y = 'Number of observations', title = 'CC')

SizeOfClusters %>%
	filter(prime_mover == 'GT') %>%
	mutate(cluster = as.factor(cluster)) %>%
	ggplot(aes(x = cluster, y = n)) +
	geom_hline(aes(yintercept = num_rows_evenly_split), linetype = 'dashed') +
	geom_col(fill = '#20A2E3') +
	scale_y_continuous(labels = scales::comma_format()) +
	facet_wrap(~num_clusters, nrow = 1, scales = 'free_x') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = 'Clusters', y = 'Number of observations', title = 'GT')

SizeOfClusters %>%
	filter(prime_mover == 'ST') %>%
	mutate(cluster = as.factor(cluster)) %>%
	ggplot(aes(x = cluster, y = n)) +
	geom_hline(aes(yintercept = num_rows_evenly_split), linetype = 'dashed') +
	geom_col(fill = '#20A2E3') +
	scale_y_continuous(labels = scales::comma_format()) +
	facet_wrap(~num_clusters, nrow = 1, scales = 'free_x') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = 'Clusters', y = 'Number of observations', title = 'ST')


# As we cluster, look at the explanatory power of clustering on different
# variables. Pull out the top 5 from each prime_mover type, and visualize!

variables_for_alternate_sanity_check <-
	sort(unique(c(variables_for_regressions,
	variables_for_sanity_check_cc, 
	variables_for_sanity_check_gt, 
	variables_for_sanity_check_st)))

ModsFit <-
	Clusters %>%
		select(prime_mover, num_clusters, cluster, rowid) %>%
		unnest(c(cluster, rowid)) %>%
		inner_join(Data, by = c('prime_mover', 'rowid')) %>%
		select(prime_mover, num_clusters, cluster, 
					 all_of(variables_for_alternate_sanity_check)) %>%
		mutate_at(c('prime_mover', 'cluster'), factor, ordered = F) %>%
		gather(variable, value, -prime_mover, -num_clusters, -cluster) %>%
		group_by(prime_mover, variable, num_clusters) %>%
		mutate(value = as.vector(scale(value))) %>%
		drop_na(value)  %>% # I think some variables didn't have variance so the scaling didn't work
		nest %>%
		mutate(
			mod1 = map(data, lm, formula = 'value ~ cluster'),
			mod0 = map(data, lm, formula = 'value ~ 1')
		) %>% 
	ungroup

GOFFull <-
	ModsFit %>%
		mutate(residuals = map(mod1, 'residuals')) %>%
		select(prime_mover, num_clusters, variable, residuals) %>%
		unnest(residuals) %>% 
		group_by(prime_mover, num_clusters, variable) %>%
		summarize(
			rmse = sqrt(mean(residuals**2))
		) %>%
		ungroup

RankedVariables <-
	GOFFull %>%
		group_by(prime_mover, variable) %>%
		summarize(delta = max(rmse) - min(rmse)) %>%
		ungroup %>%
		group_by(prime_mover) %>%
		slice_max(order_by = delta, n = 5) %>%  # NB this is where we limit to top 5
		ungroup
	
GOFNull <-
	ModsFit %>%
		group_by(prime_mover, variable) %>%
		filter(num_clusters == min(num_clusters)) %>%  # we only need one null model per prime mover
		ungroup %>%
		mutate(residuals = map(mod0, 'residuals')) %>%
		select(prime_mover, variable, residuals) %>%
		unnest(residuals) %>%
		group_by(prime_mover, variable) %>%
		summarize(
			rmse = sqrt(mean(residuals**2))
		) %>%
		ungroup %>%
		mutate(num_clusters = 1)

plot_rmse_by_cluster <- function(var_prime_mover){
	x_labels <- c('Unclustered', str_c(seq(2, 5)))
	GOFFull %>%
		bind_rows(GOFNull) %>%
		inner_join(RankedVariables, by = c('prime_mover', 'variable')) %>%
		filter(prime_mover == var_prime_mover) %>%
		# mutate(variable = fct_reorder(variable, delta)) %>%
		ggplot(aes(x = num_clusters, y = rmse)) +#, group = variable, color = variable)) +
		geom_line() +
		facet_wrap(~variable) +
		scale_x_continuous(labels = x_labels, breaks = seq(1, 5)) +
		labs(x = 'Clusters', y = 'RMSE (standard deviations)', color = '',
				 title = 'Variables with the greatest change in RMSE',
				 subtitle = var_prime_mover) +
		theme(
			axis.ticks = element_blank(),
			text = element_text(family = 'serif')
		)
}
plot_rmse_by_cluster('CC')
plot_rmse_by_cluster('GT')
plot_rmse_by_cluster('ST')

CollectedVariables <-
	RankedVariables %>%
		bind_rows(VariablesForSanityCheck) %>%
		distinct(prime_mover, variable)


# Look at the cluster-level characteristics
show_cluster_splot <- function(prime_mover_var, num_clusters_var) {
	# Custom scatterplot matrix using GGally
	
	custom_density <- function(data, mapping, ...) {
		p <- ggplot(data = data, mapping = mapping) +
			geom_density(alpha = 0.25, aes(fill = cluster, ...))
	}
	custom_lower <- function(data, mapping, ...) {
		p <- ggplot(data = data, mapping = mapping) +
			geom_smooth(method = 'lm', formula = 'y~x', aes(color = cluster, ...))
	}
	
	variables_to_select <-
		CollectedVariables %>%
			filter(prime_mover == prime_mover_var) %>%
			arrange(variable) %>%
			pull(variable)
		
	# num_clusters_var = 2 
	# prime_mover_var = 'CC'
	title_var = str_c(prime_mover_var, num_clusters_var, sep = ': ')
	Clusters %>%
		filter((num_clusters == num_clusters_var) & (prime_mover == prime_mover_var)) %>%
		select(rowid, cluster) %>%
		unnest(everything()) %>%
		inner_join(Data, by = 'rowid') %>%
		select(cluster, all_of(variables_to_select)) %>%
		mutate(cluster = factor(cluster)) %>%
		ggpairs(., columns = seq(2, length(.)), 
						ggplot2::aes(color = cluster),
												 # fill = cluster),
			diag = list(continuous = custom_density),
			lower = list(continuous = custom_lower),
			upper = list(continuous =
									 	wrap('cor', use = 'pairwise.complete.obs', digits = 1, size = 3))) +
		scale_x_continuous(n.breaks = 3) +
		theme(
			axis.ticks = element_blank(),
			text = element_text(family = 'serif'),
			strip.text.y.right = element_text(angle = 0)
		) +
		labs(title = title_var)
}

# Loop through all clusters and plot the results
expand_grid(
	prime_mover_var = c('CC', 'GT', 'ST'),
	num_clusters_var = seq(2, 5)) %>%
	mutate(
		fn = map2_chr(prime_mover_var, num_clusters_var, ~str_c(
			'results/', 'clusters_', .x, '_', .y, '.png', sep = '')),
		img = map2(prime_mover_var, num_clusters_var, show_cluster_splot),
		wrt = map2(img, fn, ~ggsave(filename = .y, plot = .x, units = 'in', width = 20, height = 9))
		)

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
write_csv(NumClusters, 'clean_data/num_clusters.csv')

ClusteredData <-
	Clusters %>%
		semi_join(NumClusters, by = c('num_clusters', 'prime_mover')) %>%
		select(rowid, cluster) %>%
		unnest(c(rowid, cluster)) %>%
		full_join(Data, by = 'rowid')
write_csv(ClusteredData, 'clean_data/clustered_data.csv')

