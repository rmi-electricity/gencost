# Regression models

library(tidyverse)
library(skimr)
library(conflicted)
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

# Test different regression models
ClusteredData %>%
	mutate(cluster = '(None)') %>%
	bind_rows(ClusteredData) %>%
	select(rowid, prime_mover, cluster, all_of(variables_for_regressions)) %>%
	group_by(prime_mover, cluster) %>%
	nest %>%
	expand_grid(resample_i = seq(1, 5)) %>%
	mutate(
		train = map(data, sample_frac, size = 0.75, replace = F),
		test = map2(data, train, anti_join, by = 'rowid'),
		# variables = map(data, get_variable_names_with_variance),
		# data = map2(data, variables, select),
		# lm_fit = map(data, lm, formula = 'real_opex ~ 0 + .'),
		# glm_fit = map(data, glm, formula = 'real_opex ~ 0 + .', family = poisson())
	)
:w

	
	
	
