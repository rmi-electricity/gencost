# GenCost workflow
# 5. Final Transformations
# Andrew Bartnof, for RMI, 2023

# Combine the clustered data with the modelled coefficients in order to
# calculate our outcome variables, modelling power plant costs.

#### Import libraries ####

library(tidyverse)
library(skimr)
library(conflicted)
library(arrow)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

#### Load data ####
my_folder <- '~/Downloads/temp_folder/'
setwd(my_folder)

# Raw datasets
DataBySubplant <- arrow::read_parquet('data_by_subplant.parquet')
EternallyPresent <- arrow::read_parquet('epd.parquet')

# Datasets created by prev scripts
CleanedDataBySubplant <- read_csv('cleaned_data_by_subplant_data.csv')
CleanedEternallyPresent <- read_csv('cleaned_eternally_present.csv')

ChosenCoefficients <- read_csv('chosen_coefficients.csv')
ChosenFormulas <- read_csv('chosen_formulas.csv')
# ChosenFormulas <- read_csv('clean_data/chosen_formulas.csv')
# AllPossibleCoefficients <- read_csv('clean_data/all_possible_coefficients.csv')
# FittedValues <- read_csv('clean_data/fitted_values.csv')

# Clusters
ClustersFit <- readRDS('clusters_fit.RDS')
ClusteredEternallyPresent <- readRDS('clustered_eternally_present.RDS')

#### Fit Vom Fom Som, and om_per_mhw ####
get_misc_variables <- function(X){
	# Insert DataBySubplant, HistoricalData, or EternallyPresent
	X %>%
		rowid_to_column %>%
		select(rowid, capacity_mw, generator_starts, gross_generation_mwh)
}

MiscVariablesDataBySubplant <- get_misc_variables(DataBySubplant)
MiscVariablesEternallyPresent <- get_misc_variables(EternallyPresent)

get_vom_etc <- function(XCls, XCleaned, XMisc){
	# Get vom fom som and om_per_mwh
	# Note that vom, fom, and som are limited here to not exceed the central 80% of the values, per cluster; any value below 10% or higher than 90% is floored or ceilinged, respectively.
	# XCls: a table that assigns rowid to cluster
	# XCleaned: a table that's been cleaned in the initial_transformations.R script
	# XMisc: a table that has invariate values that we'll need from the raw datasets
	# for example, you could input the following tables: ClusteredHistoricalData, CleanedHistoricalData, MiscVariablesHistoricalData
	CTE <-
		XCls %>%
		unnest(c(rowid, cls)) %>%
		select(prime_mover, rowid, cls) %>%
		# Join the full dataset based on prime_mover and row_id
		inner_join(XCleaned, by = c('prime_mover', 'rowid')) %>%
		pivot_longer(
			cols = !c(prime_mover, rowid, cls),
			names_to = 'variable',
			values_to = 'value'
		) %>%
		# Once the data is in long format, inner join to the relevant variables
		# for the models we've chosen
		inner_join(ChosenCoefficients, by = c('prime_mover', 'cls', 'variable')) %>%
		mutate(value_x_coef = value * coefficient) %>%
		group_by(rowid, prime_mover, cls, category) %>%
		summarize(sum_value_x_coef = sum(value_x_coef)) %>%
		ungroup %>%
		spread(category, sum_value_x_coef) %>%
		# # Add the table that collects capacity_mw, etc
		inner_join(XMisc, by = 'rowid') %>%
		# Note that this will throw missing values if any of the denominators
		# are zero
		mutate(
			fom = fixed / (capacity_mw * 1000),
			vom = variable / gross_generation_mwh,
			som = start / (capacity_mw * generator_starts * 1000)
		)

	Limits <-
		CTE %>%
		select(prime_mover, cls, vom, fom, som) %>%
		gather(variable, value, -prime_mover, -cls) %>%
		drop_na(value) %>%  # we get these from zeros in the denom.
		group_by(prime_mover, cls, variable) %>%
		summarize(
			low = quantile(value, 0.1),
			high = quantile(value, 0.9)
		) %>%
		ungroup

	ValuesWithinBoundaries <-
		CTE %>%
		select(rowid, prime_mover, cls, vom, fom, som) %>%
		gather(variable, value, -rowid, -prime_mover, -cls) %>%
		left_join(Limits, by = c('prime_mover', 'cls', 'variable')) %>%
		mutate(
			value_adj = case_when(
				value > high ~ high,
				value < low ~ low,
				TRUE ~ value
			)
		) %>%
		select(rowid, prime_mover, cls, variable, value_adj) %>%
		spread(variable, value_adj)

	Output <-
		ValuesWithinBoundaries %>%
		left_join(XMisc, by = 'rowid') %>%
		mutate(
			om_per_mwh = (
				(som * capacity_mw * generator_starts * 1000 + fom * capacity_mw * 1000) / gross_generation_mwh)
			+ vom
		) %>%
		select(rowid, cls, prime_mover, fom, vom, som, om_per_mwh)
}

ResultsEternallyPresent <-
	get_vom_etc(
		XCls = ClusteredEternallyPresent,
		XCleaned = CleanedEternallyPresent,
		XMisc =  MiscVariablesEternallyPresent
	)
# print(ResultsEternallyPresent)

ResultsDataBySubplant <-
	get_vom_etc(
		XCls = ClustersFit,
		XCleaned = CleanedDataBySubplant,
		XMisc =  MiscVariablesDataBySubplant
	)

#### Export results ####
EternallyPresent %>%
	rowid_to_column %>%
	select(rowid, plant_id_eia, generator_id, report_date) %>%
	mutate(report_date = lubridate::as_date(report_date)) %>%
	inner_join(ResultsEternallyPresent) %>%
	write_csv('results_eternally_present.csv')

DataBySubplant %>%
	rowid_to_column %>%
	select(rowid, plant_id_eia, report_date) %>%
	mutate(report_date = lubridate::as_date(report_date)) %>%
	inner_join(ResultsDataBySubplant) %>%
	write_csv('results_data_by_subplant.csv')
