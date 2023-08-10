# Analysis of clusters
# Load sanity check variables
# Cluster sizes
# Summary statistics of characteristics
# Fit regressions
# Show regression GoF (lm summary)
# Show regression GoF (dataviz showing CV)

library(tidyverse)
library(skimr)
library(conflicted)
library(leaps)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')
set.seed(1)	

#### Load files ####

setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

ClusteredData <- readRDS('clean_data/clustered_data.RDS')
ClusteredHist <- readRDS('clean_data/clustered_hist.RDS')
DataBySubplant <- read_csv('clean_data/cleaned_data_by_subplant.csv') %>%
	filter(consolidated_regression_filter)  # regressions will be on filtered data.
LongVariableKey <- read_csv('clean_data/long_variable_key.csv')

#### Establish variables ####
variables_for_sanity_check_cc <- c('age_in_report_year', 'capacity_mw', 
																	 'generator_starts', 'gross_cf', 'natural_gas_fraction', 'petroleum_fraction', 
																	 'minor_fuels_fraction')

variables_for_sanity_check_gt <- c('age_in_report_year', 'capacity_mw', 
																	 'generator_starts', 'gross_cf', 'natural_gas_fraction', 'petroleum_fraction',  
																	 'minor_fuels_fraction')

variables_for_sanity_check_st <- c('age_in_report_year', 'capacity_mw', 
																	 'generator_starts', 'gross_cf', 'coal_fraction', 'natural_gas_fraction', 
																	 'petroleum_fraction', 'minor_fuels_fraction')

VariablesForSanityCheck <-
	tribble(
		~prime_mover, ~variables,
		'CC', variables_for_sanity_check_cc,
		'GT', variables_for_sanity_check_gt,
		'ST', variables_for_sanity_check_st
	)

#### Correlations ####
JoinmeVariables <-
	LongVariableKey %>%
		filter(variable_type != 'unused') %>%
		select(prime_mover, variable) %>%
		nest(data = variable) %>%
		mutate(columns = map(data, pull)) %>%
		select(prime_mover, columns)

numeric_variables <-
	DataBySubplant %>%
		select_if(is.numeric) %>%
		colnames

DataBySubplant %>%
	select(prime_mover, all_of(numeric_variables)) %>%
	group_by(prime_mover) %>%
	nest %>%
	ungroup %>%
	left_join(JoinmeVariables) %>%
	mutate(
		data = map2(data, columns, select),
		Cor = map(data, cor, method = 's', use = 'pairwise.complete.obs'),
		Cor = map(Cor, as.data.frame),
		Cor = map(Cor, rownames_to_column, 'variable1')
	) %>%
	select(prime_mover, Cor) %>%
	unnest(Cor) %>%
	gather(variable2, cor, -prime_mover, -variable1) %>%
	drop_na(cor) %>%
	ggplot(aes(x = variable1, y = variable2, fill = cor, label = round(cor, 1))) +
	geom_raster() +
	geom_text(size = 2) +
	scale_fill_gradient2(low = 'red', mid = 'white', high = 'blue',
											 limits = c(-1, 1)) +
	scale_y_discrete(limits = rev) +
	facet_wrap(~prime_mover, scales = 'free') +
	theme(axis.ticks = element_blank(),
				legend.position = 'bottom', 
				axis.text.x = element_text(angle = 90, vjust = 0.5, hjust=1)) +
	labs(x = '', y = '')
#



#### Cluster sizes ####
# How big would the clusters be if they were evenly sized:
# per prime_mover: Num rows / num_clusters
EvenlySizedReference <-
	DataBySubplant %>%
		count(prime_mover) %>%
		expand_grid(num_clusters = seq(1, 15)) %>%
		mutate(even_size = n / num_clusters) %>%
		select(prime_mover, num_clusters, even_size)

# Actual sizes:
ClusteredData %>%
	select(prime_mover, num_clusters, cluster) %>%
	unnest(cluster) %>%
	count(prime_mover, num_clusters, cluster) %>%
	left_join(EvenlySizedReference, by = c('prime_mover', 'num_clusters')) %>%
	filter(prime_mover == 'CC') %>%
	ggplot(aes(x = cluster, y = n)) +
	geom_hline(aes(yintercept = even_size), linetype = 'dashed') +
	geom_col(fill = 'dodgerblue') +
	facet_wrap(~num_clusters, scales = 'free') +
	scale_x_continuous(breaks = seq(1, 15)) +
	theme(
		axis.ticks = element_blank(),
		text = element_text(family = 'serif'),
		panel.grid.major.x = element_blank(),
		panel.grid.minor.x = element_blank()
	) +
	labs(x = 'Cluster', y = 'Rows per cluster', title = 'CC: Rows per cluster, per clustering schema',
			 caption = 'Reference line indicates how large the clusters would be if they were evenly-sized')

ClusteredData %>%
	select(prime_mover, num_clusters, cluster) %>%
	unnest(cluster) %>%
	count(prime_mover, num_clusters, cluster) %>%
	left_join(EvenlySizedReference, by = c('prime_mover', 'num_clusters')) %>%
	filter(prime_mover == 'GT') %>%
	ggplot(aes(x = cluster, y = n)) +
	geom_hline(aes(yintercept = even_size), linetype = 'dashed') +
	geom_col(fill = 'dodgerblue') +
	facet_wrap(~num_clusters, scales = 'free') +
	scale_x_continuous(breaks = seq(1, 15)) +
	theme(
		axis.ticks = element_blank(),
		text = element_text(family = 'serif'),
		panel.grid.major.x = element_blank(),
		panel.grid.minor.x = element_blank()
	) +
	labs(x = 'Cluster', y = 'Rows per cluster', title = 'GT: Rows per cluster, per clustering schema',
			 caption = 'Reference line indicates how large the clusters would be if they were evenly-sized')

ClusteredData %>%
	select(prime_mover, num_clusters, cluster) %>%
	unnest(cluster) %>%
	count(prime_mover, num_clusters, cluster) %>%
	left_join(EvenlySizedReference, by = c('prime_mover', 'num_clusters')) %>%
	filter(prime_mover == 'ST') %>%
	ggplot(aes(x = cluster, y = n)) +
	geom_hline(aes(yintercept = even_size), linetype = 'dashed') +
	geom_col(fill = 'dodgerblue') +
	facet_wrap(~num_clusters, scales = 'free') +
	scale_x_continuous(breaks = seq(1, 15)) +
	theme(
		axis.ticks = element_blank(),
		text = element_text(family = 'serif'),
		panel.grid.major.x = element_blank(),
		panel.grid.minor.x = element_blank()
	) +
	labs(x = 'Cluster', y = 'Rows per cluster', title = 'ST: Rows per cluster, per clustering schema',
			 caption = 'Reference line indicates how large the clusters would be if they were evenly-sized')

#### Sanity check variable characteristics ####

NestedDataForSanityCheck <-
	ClusteredData %>%
		unnest(c(rowid, cluster)) %>%
		inner_join(DataBySubplant, by = c('prime_mover', 'rowid')) %>%
		group_by(prime_mover, num_clusters, cluster) %>%
		nest %>%
		ungroup %>%
		left_join(VariablesForSanityCheck, by = 'prime_mover') %>%
		mutate(
			data = map2(data, variables, select),
			Cor = map(data, cor, use = 'pairwise.complete.obs', method = 's'),
			Cor = map(Cor, as.data.frame),
			Cor = map(Cor, rownames_to_column, 'variable1')
		)

Plotme <-
	NestedDataForSanityCheck %>%
		select(prime_mover, num_clusters, cluster, Cor) %>%
		unnest(Cor) %>%
		gather(variable2, cor, -prime_mover, -num_clusters, -cluster, -variable1) %>%
		drop_na(cor)

prime_mover_var <- 'CC'
num_clusters_var <- 5

write_corplot <- function(Plotme, prime_mover_var, num_clusters_var){
	fn <- str_c('results/correlations_', prime_mover_var, num_clusters_var, '.png')
	title_var <- str_c(prime_mover_var, ': ', num_clusters_var, ' clusters')
	
	g <-
		Plotme %>%
			filter(
				prime_mover == prime_mover_var, 
				num_clusters == num_clusters_var
			) %>%
			drop_na %>%
			ggplot(aes(x = variable1, y = variable2, fill = cor)) +
			scale_y_discrete(limits = rev) +
			geom_raster() +
			scale_fill_distiller(palette = "RdBu", direction = 1, 
													 breaks = seq(-1, 1, by = 1), limits = c(-1, 1)) +
			facet_wrap(~cluster) +
			theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust=1),
						panel.grid = element_blank(),
						axis.ticks = element_blank(),
						text = element_text(family = 'serif'),
						panel.background = element_blank(),
						legend.position = 'bottom')	+
			labs(x = '', y = '', title = title_var, fill = 'Spearman\'s Rho')
	ggsave(plot = g, filename = fn, width = 20, height = 9, units = 'in')
}

Plotme <-
	NestedDataForSanityCheck %>%
		select(-variables, -Cor) %>%
		unnest(data) %>%
		gather(variable, value, -prime_mover, -num_clusters, -cluster) %>%
		drop_na(value) %>%
		mutate_at(c('num_clusters', 'cluster'), factor, ordered = F) %>%
		group_by(prime_mover, num_clusters, variable) %>%
		mutate(value = as.vector(scale(value))) %>%
		ungroup %>%
		group_by(prime_mover, num_clusters, cluster, variable) %>%
		summarize(
			n = n(),
			mean = mean(value),
			high = mean(value) + sd(value),
			low = mean(value) - sd(value)
		) %>%
		ungroup

PlotmeUnstandardized <-
	NestedDataForSanityCheck %>%
		select(-variables, -Cor) %>%
		unnest(data) %>%
		gather(variable, value, -prime_mover, -num_clusters, -cluster) %>%
		drop_na(value) %>%
		mutate_at(c('num_clusters', 'cluster'), factor, ordered = T) %>%
		group_by(prime_mover, num_clusters, variable) %>%
		mutate(value = as.vector(scale(value))) %>%
		ungroup

g <-
PlotmeUnstandardized %>%
	filter(prime_mover == 'ST', num_clusters <= 6) %>%
	# mutate_at('cluster', fct_rev) %>%
	ggplot(aes(x = cluster, y = value)) +
	geom_boxplot(varwidth = T) +
	facet_grid(num_clusters ~ variable) +
	coord_cartesian(ylim = c(-3, 3)) +
	# coord_flip(ylim = c(-3, 3)) +
	# coord_cartesian(ylim = c(-3, 3)) +
	# scale_x_discrete(labels = labels) +
	scale_y_continuous(breaks = seq(-3, 3, by = 3), minor_breaks = seq(-3, 3, by = 1)) +
	theme(legend.position = 'bottom',
				axis.ticks = element_blank(),
				text = element_text(family = 'serif'))  +
	labs(x = 'Cluster', y = 'Z-score', title = 'ST')
ggsave(plot = g, filename = '~/Downloads/st_consolidated_boxplots_tall.png', width = 20, height = 10, units = 'in')

mask <- seq(1, 15) %% 3 == 0
labels <- rep('', 15)
labels[mask] <- seq(1,15)[mask]
labels


Plotme %>%
	filter(prime_mover == 'CC') %>%
	ggplot(aes(x = cluster)) +
	# geom_text(y = -2, aes(label = n)) +
	geom_point(aes(y = mean, size = n)) +
	geom_linerange(aes(ymin = low, ymax = high)) +
	facet_grid(num_clusters ~ variable) +
	coord_cartesian(ylim = c(-3, 3)) +
	scale_x_discrete(labels = labels) +
	scale_y_continuous(breaks = seq(-3, 3, by = 3)) +
	theme(legend.position = 'bottom',
				axis.ticks = element_blank(),
				text = element_text(family = 'serif'))  +
	labs(x = 'Cluster', y = 'Z-score', title = 'CC', caption = 'Lines indicate +/- 1 sd', size = 'Size of cluster')
	# filter(prime_mover == 'CC') %>%
	# ggplot(aes(x = cluster, y = value)) +
	# geom_boxplot() +
	# facet_grid(variable ~ num_clusters, scales = 'free')
	# print
#




#### Overall stats ####
# prime_mover_var <- 'CC'
# num_clusters_var <- 3

write_boxplot <- function(Plotme, prime_mover_var, num_clusters_var){
	fn <- str_c('results/boxplots_', prime_mover_var, num_clusters_var, '.png')
	title_var <- str_c(prime_mover_var, ': ', num_clusters_var, ' clusters')
	
	g <-
		NestedDataForSanityCheck %>%
			select(prime_mover, num_clusters, cluster, data) %>%
			unnest(data) %>%
			filter(prime_mover == prime_mover_var, num_clusters == num_clusters_var) %>%
			select(-prime_mover, -num_clusters) %>%
			gather(variable, value, -cluster) %>%
			drop_na %>%
			ggplot(aes(x = as.factor(cluster), y = value)) +
			geom_boxplot() +
			coord_flip() +
			facet_wrap(~variable, scales = 'free_x') +
			scale_x_discrete(limits = rev) +
			theme(
				axis.ticks = element_blank(),
				panel.grid.major.y = element_blank(),
				text = element_text(family = 'serif')
			) +
			labs(x = 'Cluster', y = '', title = title_var)
		ggsave(plot = g, filename = fn, width = 20, height = 9, units = 'in')
}
	
	
for (i in c('CC', 'GT', 'ST')){
	for (j in seq(1, 15)){
		write_corplot(Plotme, prime_mover_var = i, num_clusters_var = j)
		write_boxplot(Plotme, prime_mover_var = i, num_clusters_var = j)
	}
}

#### Define a new regression model for each cluster ####
# Filter down to only legal variables
# Note the necessary/core variables

ClusteredData %>%
	unnest(c(rowid, cluster)) %>%
	left_join(DataBySubplant, by = c("prime_mover", "rowid")) %>%
	group_by(prime_mover, num_clusters, cluster) %>%
	nest %>%
	ungroup

legal_variables <-
	LongVariableKey %>%
		filter(prime_mover == 'ST', variable_type != 'unused') %>%
		pull(variable)

core_variables <-
	LongVariableKey %>%
		filter(prime_mover == 'ST', variable_type == 'core') %>%
		pull(variable)

X <- DataBySubplant %>% select(all_of(legal_variables)) %>% as.data.frame
y <- DataBySubplant$real_opex
# leaps(x = X, y = y, 
# 			names = colnames(X), method = 'adjr2', int = FALSE, 
# 			leaps.setup(force.in = core_variables))
regsubsets_fit <- regsubsets(x = X, y = y,
						 nvmax = 25, method = "forward",
						 force.in = core_variables,
						 intercept = FALSE)
summary.regsubsets <- summary(regsubsets_fit)
# summary.regsubsets
summary.regsubsets$adjr2
summary.regsubsets$which
which.max(summary.regsubsets$adjr2)
mask <- summary.regsubsets$which[9,]
sort(colnames(summary.regsubsets$which)[mask])


CoreVariables <-
	LongVariableKey %>%
		filter(variable_type == 'core') %>%
		select(prime_mover, variable) %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		mutate(core_variables = map(data, pull)) %>%
		ungroup %>%
		select(prime_mover, core_variables)

LegalVariables <-
	LongVariableKey %>%
		filter(variable_type != 'unused') %>%
		select(prime_mover, variable) %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		mutate(legal_variables = map(data, pull)) %>%
		ungroup %>%
		select(prime_mover, legal_variables)

ClusteredData %>%
	unnest(c(rowid, cluster)) %>%
	left_join(DataBySubplant, by = c("prime_mover", "rowid")) %>%
	group_by(prime_mover, num_clusters, cluster) %>%
	nest %>%
	ungroup %>%
	left_join(CoreVariables, by = 'prime_mover') %>%
	left_join(LegalVariables, by = 'prime_mover') %>%
	head(4) %>%
	# slice(5) %>%
	mutate(nrow = map_dbl(data, nrow)) %>%
	select(nrow)
	print
	
	
	
	head(5) %>%
	mutate(
		y = map(data, pull, 'real_opex'),
		hypothesis_space = map2(data, legal_variables, select),
		leap_fit = map2(hypothesis_space, y, ~regsubsets(x = .x, y = .y, method = 'forward'))
		# leap_fit = pmap(list(x = hypothesis_space, y = y, force.in = core_variables),
		# 								regsubsets, method = 'forward', intercept = FALSE)
	) %>%
	print

regsubsets_fit <- regsubsets(x = X, y = y,
						 nvmax = 25, method = "forward",
						 force.in = core_variables,
						 intercept = FALSE)







