# Descriptive statistics:
# 	nrow
#		missing data
#		means per group
#		corelations between variables?

library(tidyverse)
library(skimr)
library(conflicted)
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')
Data <- read_csv('clean_data/data.csv', col_types = c(
	rowid = 'i', prime_mover = 'c', plant_id_eia = 'f', 
	consolidated_regression_filter = 'l', .default = 'd'))

variables_for_regressions <- readRDS('clean_data/variables_for_regressions.RDS')
variables_for_sanity_check <- readRDS('clean_data/variables_for_sanity_check.RDS')
variables_for_subsetting <- readRDS('clean_data/variables_for_subsetting.RDS')

ConsolidatedRegressionFilter <-
	Data %>%
		select(prime_mover, consolidated_regression_filter) %>%
		mutate(
			consolidated_regression_filter = factor(consolidated_regression_filter),
			consolidated_regression_filter = fct_explicit_na(consolidated_regression_filter),
			consolidated_regression_filter = ordered(consolidated_regression_filter, c('TRUE', 'FALSE', '(Missing)'))
	  ) %>%
		count(prime_mover, consolidated_regression_filter, .drop = F) %>%
		group_by(prime_mover) %>%
		mutate(prop = n / sum(n)) %>%
		ungroup

ConsolidatedRegressionFilter %>%
	ggplot(aes(x = consolidated_regression_filter, y = n)) +
	geom_col() +
	geom_text(aes(label = scales::comma(n)), vjust = -1) +
	facet_wrap(~prime_mover, nrow = 1) +
	# scale_y_continuous(labels = scales::comma_format()) +
	expand_limits(y = 8000) +
	labs(x = 'Results of regression filter', y = 'n observations') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		axis.text.y = element_blank()
	)

ConsolidatedRegressionFilter %>%
	ggplot(aes(x = consolidated_regression_filter, y = prop)) +
	geom_col() +
	geom_text(aes(label = scales::percent(prop, 1)), vjust = -1) +
	facet_wrap(~prime_mover, nrow = 1) +
	scale_y_continuous(labels = scales::percent_format()) +
	expand_limits(y = 1) +
	labs(x = 'Results of regression filter', y = '% observations') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		axis.text.y = element_blank()
	)

MissingData <-
	Data %>%
		select(-plant_id_eia) %>%
		gather(variable, value, -prime_mover) %>%
		mutate(is_missing = is.na(value)) %>%
		group_by(prime_mover, variable) %>%
		summarize(
			prop_missing = mean(is_missing),
			num_missing = sum(is_missing),
			num_total = n()
		) %>%
		ungroup

MissingData %>%
	mutate(label_prop_missing = if_else(
		prop_missing > 0, scales::percent(prop_missing), NA_character_)) %>%
	ggplot(aes(x = prime_mover, y = variable, fill = prop_missing, label = label_prop_missing)) +
	geom_raster() +
	geom_text() +
	labs(x = 'Prime mover', y = 'Variable', fill = '% missing', title = 'Missing data') +
	scale_fill_gradient(low = "black", high = "lightblue", limits = c(0, 0.1), labels = scales::percent_format()) +
	scale_y_discrete(limits = rev) +
	theme(axis.ticks = element_blank(), 
				panel.background = element_blank())

Data %>%
	count(prime_mover) %>%
	ggplot(aes(x = prime_mover, y = n)) +
	geom_col() +
	scale_y_continuous(labels = scales::comma_format()) +
	labs(x = 'Prime mover', y = 'Observations') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank()
	)

Data %>%
	# overly busy descriptive stats
	mutate(prime_mover = 'Overall') %>%
	bind_rows(Data) %>%
	mutate(prime_mover = ordered(prime_mover, c('Overall', 'CC', 'GT', 'ST'))) %>%
	select(-plant_id_eia) %>%
	gather(variable, value, -prime_mover) %>%
	drop_na %>%
	ggplot(aes(x = prime_mover, y = value)) +
	geom_boxplot(alpha = 0.1) +
	coord_flip() +
	scale_x_discrete(limits = rev) +
	facet_wrap(~variable, scales = 'free_x')

Data %>%
	# overly busy descriptive stats, but in a table
	mutate(prime_mover = 'Overall') %>%
	bind_rows(Data) %>%
	mutate(prime_mover = ordered(prime_mover, c('Overall', 'CC', 'GT', 'ST'))) %>%
	select(-plant_id_eia) %>%
	group_by(prime_mover) %>%
	skim
