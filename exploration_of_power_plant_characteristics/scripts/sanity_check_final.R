library(tidyverse)
library(skimr)
library(conflicted)
library(arrow)
# library(lubridate)
# library(flexclust)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

#### Load data ####
DataBySubplant <- arrow::read_parquet('input_data/data_by_subplant.parquet')

CleanedDataBySubplant <- read_csv('clean_data/cleaned_data_by_subplant_data.csv')
ChosenFormulas <- read_csv('clean_data/chosen_formulas.csv')
AllPossibleCoefficients <- read_csv('clean_data/all_possible_coefficients.csv')
FittedValues <- read_csv('clean_data/fitted_values.csv')

ClustersFit <- readRDS('clean_data/clusters_fit.RDS')

# Sanity check: for chosen formulas, for databysubplant, 
# multiply coef by values and make sure they equal mods' fitted_values

JoinmeCoefficients <-
	AllPossibleCoefficients %>%
		inner_join(ChosenFormulas, by = c('prime_mover', 'cls', 'pull_size', 'formula'))

TempSumValueXCoef <-
	ClustersFit %>%
		select(prime_mover, rowid, cls) %>%
		unnest(c(rowid, cls)) %>%
		inner_join(CleanedDataBySubplant, by = c('prime_mover', 'rowid')) %>%
		gather(variable, value, -prime_mover, -rowid, -cls) %>%
		inner_join(JoinmeCoefficients, by = c('prime_mover', 'cls', 'variable')) %>%
		mutate(value_x_coef = value * coefficient) %>%
		group_by(rowid) %>%
		summarize(sum_value_x_coef = sum(value_x_coef)) %>%
		ungroup

FittedValues %>%
	inner_join(TempSumValueXCoef) %>%
	select(sum_value_x_coef, fitted_values) %>%
	mutate(is_same = near(sum_value_x_coef, fitted_values, tol = 1)) %>%
	skim(is_same)

# Vom Fom Som
JoinmeMiscVariables <-
	DataBySubplant %>%
		rowid_to_column %>%
		select(rowid, capacity_mw, generator_starts, gross_generation_mwh)

JoinmeCoefficients <-
	AllPossibleCoefficients %>%
		inner_join(ChosenFormulas, by = c('prime_mover', 'cls', 'pull_size', 'formula'))

FomVomSom <-
	ClustersFit %>%
		select(prime_mover, rowid, cls) %>%
		unnest(c(rowid, cls)) %>%
		inner_join(CleanedDataBySubplant, by = c('prime_mover', 'rowid')) %>%
		gather(variable, value, -prime_mover, -rowid, -cls) %>%
		inner_join(JoinmeCoefficients, by = c('prime_mover', 'cls', 'variable')) %>%
		mutate(value_x_coef = value * coefficient) %>%
		group_by(rowid, category) %>%
		summarize(sum_value_x_coef = sum(value_x_coef)) %>%
		ungroup %>%
		spread(category, sum_value_x_coef) %>%
		inner_join(JoinmeMiscVariables, by = 'rowid') %>%
		mutate(
			fom = fixed / (capacity_mw * 1000),
			vom = variable / gross_generation_mwh,
			som = start / (capacity_mw * generator_starts * 1000),
			om_per_mwh = (
				(som * capacity_mw * generator_starts * 1000 + fom * capacity_mw * 1000) / gross_generation_mwh) 
				+ vom
		) %>%
		select(rowid, fom, vom, som, om_per_mwh)

ClusteredMetrics <-
	ClustersFit %>%
		select(prime_mover, rowid, cls) %>%
		unnest(c(rowid, cls)) %>%
		inner_join(FomVomSom, by = 'rowid') %>%
		select(-rowid) %>%
		gather(variable, value, -prime_mover, -cls)

# Histograms
ClusteredMetrics %>%
	filter(variable == 'om_per_mwh')  %>%
	ggplot(aes(x = ordered(cls), y = value)) +
	geom_hline(yintercept = 0, color = 'grey20') +
	geom_boxplot(varwidth = T, alpha = 0.5) +
	facet_wrap(~prime_mover) +
	coord_cartesian(ylim = c(0, 300)) +
	theme(axis.ticks = element_blank(),
				panel.grid.major.x = element_blank(),
				text = element_text(family = 'serif')) +
	labs(x = 'Cluster', y = 'OM per MWH', caption = 'NB y-axis has been truncated; boxplot width represents cluster size')

ClusteredMetrics %>%
	filter(variable == 'fom')  %>%
	ggplot(aes(x = ordered(cls), y = value)) +
	geom_hline(yintercept = 0, color = 'grey20') +
	geom_boxplot(varwidth = T, alpha = 0.5) +
	facet_wrap(~prime_mover) +
	coord_cartesian(ylim = c(0, 50)) +
	theme(axis.ticks = element_blank(),
				panel.grid.major.x = element_blank(),
				text = element_text(family = 'serif')) +
	labs(x = 'Cluster', y = 'FOM', caption = 'NB y-axis has been truncated; boxplot width represents cluster size')

ClusteredMetrics %>%
	filter(variable == 'vom')  %>%
	ggplot(aes(x = ordered(cls), y = value)) +
	geom_hline(yintercept = 0, color = 'grey20') +
	geom_boxplot(varwidth = T, alpha = 0.5) +
	facet_wrap(~prime_mover) +
	coord_cartesian(ylim = c(-20, 25)) +
	theme(axis.ticks = element_blank(),
				panel.grid.major.x = element_blank(),
				text = element_text(family = 'serif')) +
	labs(x = 'Cluster', y = 'VOM', caption = 'NB y-axis has been truncated; boxplot width represents cluster size')

ClusteredMetrics %>%
	filter(variable == 'vom')  %>%
	ggplot(aes(x = ordered(cls), y = value)) +
	geom_hline(yintercept = 0, color = 'grey20') +
	geom_boxplot(varwidth = T, alpha = 0.5) +
	facet_wrap(~prime_mover) +
	coord_cartesian(ylim = c(-20, 25)) +
	theme(axis.ticks = element_blank(),
				panel.grid.major.x = element_blank(),
				text = element_text(family = 'serif')) +
	labs(x = 'Cluster', y = 'VOM', caption = 'NB y-axis has been truncated; boxplot width represents cluster size')

ClusteredMetrics %>%
	filter(variable == 'som')  %>%
	ggplot(aes(x = ordered(cls), y = value)) +
	geom_hline(yintercept = 0, color = 'grey20') +
	geom_boxplot(varwidth = T, alpha = 0.5) +
	facet_wrap(~prime_mover) +
	coord_cartesian(ylim = c(-0.05, 0.1)) +
	theme(axis.ticks = element_blank(),
				panel.grid.major.x = element_blank(),
				text = element_text(family = 'serif')) +
	labs(x = 'Cluster', y = 'SOM', caption = 'NB y-axis has been truncated; boxplot width represents cluster size')
