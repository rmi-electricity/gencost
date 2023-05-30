# Regression models

library(tidyverse)
library(skimr)
library(conflicted)
library(Metrics)
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
ClusteredData <- read_csv('clean_data/clustered_data.csv', col_types = c(
	prime_mover = 'c', plant_id_eia = 'f', cluster = 'f', 
	consolidated_regression_filter = 'l', .default = 'd')) %>%
	filter(consolidated_regression_filter)  # regressions will be on filtered data.

variables_for_regressions <- readRDS('clean_data/variables_for_regressions.RDS')

# Test different regression models, cross-validated
ModsFit <-
	ClusteredData %>%
		mutate(cluster = '(None)') %>%
		bind_rows(ClusteredData) %>%
		select(rowid, prime_mover, cluster, all_of(variables_for_regressions)) %>%
		group_by(prime_mover, cluster) %>%
		nest %>%
		expand_grid(resample_i = seq(1, 20)) %>%
		mutate(
			# Train and test sets
			train = map(data, sample_frac, size = 0.75, replace = F),
			test = map2(data, train, anti_join, by = 'rowid'),
			# Remove non-regression variables
			train = map(train, select, -'rowid'),
			variables = map(train, get_variable_names_with_variance),
			train = map2(train, variables, select),
			# Fit models
			y_true = map(test, select, 'real_opex'),
			lm_fit = map(train, lm, formula = 'real_opex ~ 0 + .'),
			y_fit_lm = map2(lm_fit, test, predict),
			glm_fit = map(train, glm, formula = 'real_opex ~ 0 + .', family = poisson()),
			y_fit_glm = map2(glm_fit, test, predict, type = 'response')
		)

ModsFit %>%
	select(prime_mover, cluster, resample_i, y_true, y_fit_lm, y_fit_glm) %>%
	unnest(c(y_true, y_fit_lm, y_fit_glm)) %>%
	rename('Linear model' = y_fit_lm, 'Poisson' = y_fit_glm) %>%
	gather(mod_type, y_fit, -prime_mover, -cluster, -resample_i, -real_opex) %>%
	group_by(prime_mover, cluster, resample_i, mod_type) %>%
	summarize(rmse = Metrics::rmse(real_opex, y_fit)) %>%
	ungroup %>%
	group_by(prime_mover, cluster, mod_type) %>%
	summarize(avg_rmse = median(rmse),
						low = median(rmse) - sd(rmse),
						high = median(rmse) + sd(rmse)) %>%
	ungroup %>%
	ggplot(aes(x = prime_mover, y = avg_rmse, group = cluster, fill = cluster)) +
	geom_col(position = 'dodge') +
	# geom_segment(position = 'dodge', aes(xend = cluster, y = low, yend = high)) +
	facet_wrap(~mod_type, scales = 'free') +
	coord_cartesian(ylim = c(0, 1000000000)) +
	scale_y_continuous(labels = scales::comma_format()) +
	theme(
		axis.ticks = element_blank(),
		legend.position = 'bottom'
	) +
	labs(x = 'Cluster', y = 'Median RMSE', 
			 title = 'Goodness of fit', fill = 'Cluster')

ModsNotCv <-
	ClusteredData %>%
		mutate(cluster = '(None)') %>%
		bind_rows(ClusteredData) %>%
		select(prime_mover, cluster, all_of(variables_for_regressions)) %>%
		group_by(prime_mover, cluster) %>%
		nest %>%
		mutate(
			# Remove non-regression variables
			variables = map(data, get_variable_names_with_variance),
			data = map2(data, variables, select),
			# Fit models
			lm_fit = map(data, lm, formula = 'real_opex ~ 0 + .'),
			y_fit_lm = map2(lm_fit, data, predict),
			glm_fit = map(data, glm, formula = 'real_opex ~ 0 + .', family = poisson()),
			y_fit_glm = map2(glm_fit, data, predict, type = 'response')
		)

ModsNotCv %>%
	ungroup %>%
	select(prime_mover, cluster, 'Linear model' = y_fit_lm, 'Poisson' = y_fit_glm) %>%
	unnest(c('Linear model', 'Poisson')) %>%
	gather(mod_type, value, -prime_mover, -cluster) %>%
	mutate(is_y_fit_neg = value < 0) %>%
	group_by(prime_mover, cluster, mod_type) %>%
	summarize(prop_neg = mean(is_y_fit_neg)) %>%
	ungroup %>%
	ggplot(aes(x = prime_mover, y = prop_neg, fill = cluster, group = cluster)) +
	geom_col(position = 'dodge') +
	facet_wrap(~mod_type, nrow = 1) +
	scale_y_continuous(labels = scales::percent_format()) +
	theme(
		axis.ticks = element_blank(),
		legend.position = 'bottom') +
	labs(x = 'Prime mover', y = '% of negative fitted values', fill = 'Cluster')

Mods <-
	ModsNotCv %>%
		ungroup %>%
		filter(
			cluster == '(None)'
		) %>%
		select(prime_mover, cluster, lm_fit)

write_rds(Mods, 'clean_data/mods.RDS')	
