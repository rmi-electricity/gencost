library(tidyverse)
library(skimr)
library(conflicted)
library(arrow)
# library(flexclust)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

#### load data ####
DataBySubplant <- arrow::read_parquet('input_data/data_by_subplant.parquet') %>%
	filter(prime_mover %in% c('CC', 'GT', 'ST'))
HistoricalData <- arrow::read_parquet('input_data/historic_data_gen_level.parquet')

VariableKey <- read_csv('input_data/regression_variables.csv', col_types = c('variable' = 'c', .default = 'f'))


AllPossibleCoefficients <- read_csv('clean_data/all_possible_coefficients.csv', col_types = c('cls' = 'i', pull_size = 'i', coefficient = 'd', .default = 'c'))
ClustersFit <- readRDS('clean_data/clusters_fit.RDS')
MapHistoricalToClusters <- readRDS('clean_data/map_historical_to_clusters.RDS')
ChosenFormulas <- read_csv('clean_data/chosen_formulas.csv')
FittedValues <- read_csv('clean_data/fitted_values.csv', col_types = c(
	'prime_mover' = 'c', 'formula' = 'c', 'cls' = 'i', 'pull_size' = 'i', 
	'rowid' = 'i', 'fitted_values' = 'd'))

ChosenCoefficients <-
	AllPossibleCoefficients %>%
		semi_join(ChosenFormulas, by = c('prime_mover', 'cls', 'pull_size', 'formula'))

# verify that the coefficients and the fitted values correspond to the same
# formulas.
xx <-
ChosenCoefficients %>%
	distinct(prime_mover, cls, formula) %>%
	arrange(prime_mover, cls, formula) %>%
	pull(formula)
yy <-
FittedValues %>%
	distinct(prime_mover, cls, formula) %>%
	arrange(prime_mover, cls, formula) %>%
	pull(formula)
all(xx == yy)

MapCleanedDataBySublantToClusters <-
	ClustersFit %>%
		select(rowid, cls) %>%
		unnest(c(rowid, cls))

#### clean_variable_key ####
FilteredVariableKey <-
	VariableKey %>%
	filter(category %in% c('fixed', 'variable', 'start'))

LongVariableKey <-
	bind_rows(
		FilteredVariableKey %>%
			select(variable, variable_type = st, category) %>%
			mutate(prime_mover = 'ST'),
		FilteredVariableKey %>%
			select(variable, variable_type = cc, category) %>%
			mutate(prime_mover = 'CC'),
		FilteredVariableKey %>%
			select(variable, variable_type = gt, category) %>%
			mutate(prime_mover = 'GT')
	) %>%
	select(prime_mover, variable, category, variable_type)

#### Define variables ####

fixed_cols <- c(
	"capacity_adj",
	"gas_fixed_adj",
	"oil_fixed_adj",
	"CHP_fixed_adj",
	"pollution_fixed_adj",
	"pulverized_coal_fixed_adj",
	"duct_burners_fixed_adj",
	"supercritical_fixed_adj",
	"age_fixed_adj",
	"oil_age_fixed_adj",
	"gas_pollution_fixed_adj"
)

variable_cols <- c(
	"gen_adj",
	"oil_variable_adj",
	"pollution_variable_adj",
	"age_variable_adj",
	"fluidized_bed_variable_adj",
	"CHP_variable_adj",
	"supercritical_variable_adj",
	"gas_age_variable_adj",
	"duct_burners_variable_adj",
	"oil_age_variable_adj"
)

start_cols <- c("starts_adj", "gas_starts_adj", "oil_starts_adj")

# MapVariableToVariableType <-
# 	# A table that allows us to map variable name to variable type
# 	tribble(
# 		~variable_type, ~variable,
# 		'variable', variable_cols,
# 		'fixed', fixed_cols,
# 		'start', start_cols
# 	) %>%
# 	unnest(variable)

#### Define functions ####

percentile = function(xx){
	# https://stackoverflow.com/questions/17557203/compute-percentile-for-a-given-value?rq=3
	ecdf(xx)(xx)
}

create_independent_variables <- function(X){
	X %>%
		rowid_to_column %>%
		mutate(
			# Now we turn to the process of regressing the FERC data to estimate capex and opex coefficients.
			# Start with (mostly) nominal, unadjusted variables for total capital cost per kW regression. The reason for this
			# is accounting - the original costs are reported as the sum of nominal costs in various years. However, as maintenance
			# capex may reasonably be expected to be constant in annual, real, state-adjusted dollars, and as cumulative
			# maintenance capex could represent some or substantially all the annual change in original costs, we do use a cumulative
			# adjusted age of observation rather than the raw age of observation to extract a real maintence capex.
			gas_fixed = natural_gas_fraction * capacity_mw,
			oil_fixed = petroleum_fraction * capacity_mw,
			other_fixed = other_gas_fraction * capacity_mw,
			coal_fixed = coal_fraction * capacity_mw,
			pollution_fixed = pollution_control_costs_per_kw * capacity_mw,
			age_fixed = age_relative_to_prime_avg * capacity_mw,
			CHP_fixed = associated_combined_heat_power * capacity_mw,
			duct_burners_fixed = duct_burners * capacity_mw,
			bypass_heat_recovery = bypass_heat_recovery * capacity_mw,
			gasification_fixed = solid_fuel_gasification * capacity_mw,
			ccs_fixed = carbon_capture * capacity_mw,
			fluidized_bed_fixed = fluidized_bed_tech * capacity_mw,
			pulverized_coal_fixed = pulverized_coal_tech * capacity_mw,
			stoker_fixed = stoker_tech * capacity_mw,
			other_comb_fixed = other_combustion_tech * capacity_mw,
			subcritical_fixed = subcritical_tech * capacity_mw,
			supercritical_fixed = supercritical_tech * capacity_mw,
			ultrasupercritical_fixed = ultrasupercritical_tech * capacity_mw,
			coal_pollution_fixed = coal_fraction * pollution_control_costs_per_kw * capacity_mw,
			coal_age_fixed = coal_fraction * age_relative_to_prime_avg * capacity_mw,
			gas_pollution_fixed = natural_gas_fraction * pollution_control_costs_per_kw * capacity_mw,
			gas_age_fixed = natural_gas_fraction * age_relative_to_prime_avg * capacity_mw,
			oil_pollution_fixed = petroleum_fraction * pollution_control_costs_per_kw * capacity_mw,
			oil_age_fixed = petroleum_fraction * age_relative_to_prime_avg * capacity_mw,
			coal_CHP_fixed = associated_combined_heat_power * coal_fraction * capacity_mw,
			gas_CHP_fixed = associated_combined_heat_power * natural_gas_fraction * capacity_mw,
			oil_CHP_fixed = associated_combined_heat_power * petroleum_fraction * capacity_mw,
			other_CHP_fixed = associated_combined_heat_power * other_gas_fraction * capacity_mw,
			age_obs_fixed = capacity_mw * age_of_observation_secular_adj,
			# cum_starts_age_obs_fixed = cum_starts * capacity_mw * age_of_observation_secular_adj,
			CHP_age_obs_fixed = associated_combined_heat_power * capacity_mw * age_of_observation_secular_adj,
			duct_burners_age_obs_fixed = duct_burners * capacity_mw * age_of_observation_secular_adj,
			bypass_hrsg_age_obs_fixed = bypass_heat_recovery * capacity_mw * age_of_observation_secular_adj,
			gasification_age_obs_fixed = solid_fuel_gasification * capacity_mw * age_of_observation_secular_adj,
			ccs_age_obs_fixed = carbon_capture * capacity_mw * age_of_observation_secular_adj,
			fluidized_bed_age_obs_fixed = fluidized_bed_tech * capacity_mw * age_of_observation_secular_adj,
			pulverized_coal_age_obs_fixed = pulverized_coal_tech * capacity_mw * age_of_observation_secular_adj,
			stoker_age_obs_fixed = stoker_tech * capacity_mw * age_of_observation_secular_adj,
			other_comb_age_obs_fixed = other_combustion_tech * capacity_mw * age_of_observation_secular_adj,
			subcritical_age_obs_fixed = subcritical_tech * capacity_mw * age_of_observation_secular_adj,
			supercritical_age_obs_fixed = supercritical_tech * capacity_mw * age_of_observation_secular_adj,
			ultrasupercritical_age_obs_fixed = ultrasupercritical_tech * capacity_mw * age_of_observation_secular_adj,
			coal_age_obs_fixed = coal_fraction * capacity_mw * age_of_observation_secular_adj,
			gas_age_obs_fixed = natural_gas_fraction * capacity_mw * age_of_observation_secular_adj,
			oil_age_obs_fixed = petroleum_fraction * capacity_mw * age_of_observation_secular_adj,
			other_age_obs_fixed = other_gas_fraction * capacity_mw * age_of_observation_secular_adj,
			
			# Now define state wage level adjusted, real cost variables for OpEx regression
			capacity_adj = wage_scale * capacity_mw,
			starts_adj = generator_starts * capacity_adj,
			gas_starts_adj = natural_gas_fraction * starts_adj,
			oil_starts_adj = petroleum_fraction * starts_adj,
			other_starts_adj = other_gas_fraction * starts_adj,
			coal_starts_adj = coal_fraction * starts_adj,
			gas_fixed_adj = natural_gas_fraction * capacity_adj,
			oil_fixed_adj = petroleum_fraction * capacity_adj,
			other_fixed_adj = other_gas_fraction * capacity_adj,
			coal_fixed_adj = coal_fraction * capacity_adj,
			# high_median_CF_fixed_adj = high_median_CF * capacity_adj,
			# mid_median_CF_fixed_adj = mid_median_CF * capacity_adj,
			# low_median_CF_fixed_adj = low_median_CF * capacity_adj,
			# median_CF_fixed_adj = median_CF * capacity_adj,
			pollution_fixed_adj = real_pollution_control_costs_per_kw * capacity_adj,
			age_fixed_adj = age_relative_to_prime_avg * capacity_adj,
			age_obs_fixed_adj = age_of_observation * capacity_adj,
			CHP_fixed_adj = associated_combined_heat_power * capacity_adj,
			duct_burners_fixed_adj = duct_burners * capacity_adj,
			bypass_hrsg_fixed_adj = bypass_heat_recovery * capacity_adj,
			gasification_fixed_adj = solid_fuel_gasification * capacity_adj,
			ccs_fixed_adj = carbon_capture * capacity_adj,
			fluidized_bed_fixed_adj = fluidized_bed_tech * capacity_adj,
			pulverized_coal_fixed_adj = pulverized_coal_tech * capacity_adj,
			stoker_fixed_adj = stoker_tech * capacity_adj,
			other_comb_fixed_adj = other_combustion_tech * capacity_adj,
			subcritical_fixed_adj = subcritical_tech * capacity_adj,
			supercritical_fixed_adj = supercritical_tech * capacity_adj,
			ultrasupercritical_fixed_adj = ultrasupercritical_tech * capacity_adj,
			coal_pollution_fixed_adj = coal_fraction * real_pollution_control_costs_per_kw * capacity_adj,
			coal_age_fixed_adj = coal_fraction * age_relative_to_prime_avg * capacity_adj,
			gas_pollution_fixed_adj = natural_gas_fraction * real_pollution_control_costs_per_kw * capacity_adj,
			gas_age_fixed_adj = natural_gas_fraction * age_relative_to_prime_avg * capacity_adj,
			oil_pollution_fixed_adj = petroleum_fraction * real_pollution_control_costs_per_kw * capacity_adj,
			oil_age_fixed_adj = petroleum_fraction * age_relative_to_prime_avg * capacity_adj,
			gen = gross_cf * capacity_mw * ifelse(report_year %% 4 ==0,8784,8760),
			gen_adj = wage_scale * gen,
			# high_median_CF_adj = high_median_CF * gen_adj,
			# mid_median_CF_adj = mid_median_CF * gen_adj,
			# low_median_CF_adj = low_median_CF * gen_adj,
			# median_CF_adj = median_CF * gen_adj,
			gas_variable_adj = natural_gas_fraction * gen_adj,
			oil_variable_adj = petroleum_fraction * gen_adj,
			other_variable_adj = other_gas_fraction * gen_adj,
			coal_variable_adj = coal_fraction * gen_adj,
			pollution_variable_adj = real_pollution_control_costs_per_kw * gen_adj,
			age_variable_adj = age_relative_to_prime_avg * gen_adj,
			age_obs_variable_adj = age_of_observation * gen_adj,
			CHP_variable_adj = associated_combined_heat_power * gen_adj,
			duct_burners_variable_adj = duct_burners * gen_adj,
			bypass_hrsg_variable_adj = bypass_heat_recovery * gen_adj,
			gasification_variable_adj = solid_fuel_gasification * gen_adj,
			ccs_variable_adj = carbon_capture * gen_adj,
			fluidized_bed_variable_adj = fluidized_bed_tech * gen_adj,
			pulverized_coal_variable_adj = pulverized_coal_tech * gen_adj,
			stoker_variable_adj = stoker_tech * gen_adj,
			other_comb_variable_adj = other_combustion_tech * gen_adj,
			subcritical_variable_adj = subcritical_tech * gen_adj,
			supercritical_variable_adj = supercritical_tech * gen_adj,
			ultrasupercritical_variable_adj = ultrasupercritical_tech * gen_adj,
			coal_pollution_variable_adj = coal_fraction * real_pollution_control_costs_per_kw * gen_adj,
			coal_age_variable_adj = coal_fraction * age_relative_to_prime_avg * gen_adj,
			gas_pollution_variable_adj = natural_gas_fraction * real_pollution_control_costs_per_kw * gen_adj,
			gas_age_variable_adj = natural_gas_fraction * age_relative_to_prime_avg * gen_adj,
			oil_pollution_variable_adj = petroleum_fraction * real_pollution_control_costs_per_kw * gen_adj,
			oil_age_variable_adj = petroleum_fraction * age_relative_to_prime_avg * gen_adj,
			# real_opex_per_kw = real_opex / capacity_mw  # is this right?
		)
	# select(rowid, prime_mover, real_opex, all_of(fixed_cols), all_of(variable_cols), all_of(start_cols), real_opex_per_kw)
}

create_consolidated_regression_filter <- function(X){
	X %>%
		mutate(real_opex_per_kw = real_opex / capacity_mw) %>%
		group_by(prime_mover) %>%
		mutate(real_opex_percentile = percentile(real_opex)) %>%
		ungroup %>%
		mutate(
			# real_opex_percentile = percentile(real_opex), # overall or per prime_mover type?
			opex_over_capex = opex_per_kw / capex_per_kw,
			is_outlier_general = ifelse(opex_over_capex >= 0.5 | opex_over_capex <= 0.002 | gross_cf > 1.1, TRUE, FALSE),
			# outlier_flag = ifelse(opex_over_capex >=0.5 | opex_over_capex <=0.002 | FERC_CF>1.1, 1, 0)) %>%
			is_safe_st = (prime_mover == 'ST') & (!is_outlier_general) &
				(gross_cf <= 1.1),  # NB this is redundent logic
			# ,data=FERC_Data,subset=(ST==1 & FERC_CF<=1.1 & outlier_flag==0))
			is_safe_cc = (prime_mover == 'CC') & (!is_outlier_general) & 
				(real_opex_percentile >= 0.03) & (real_opex_percentile <= 0.97) &
				(coal_fraction == 0),
			# ,data=FERC_Data,subset=(CC==1 & coal==0 & outlier_flag==0 & real_opex_percentile<=0.97 & real_opex_percentile>=0.03))
			is_safe_gt = (prime_mover == 'GT') & (!is_outlier_general) & 
				(real_opex_percentile<=0.97) & (real_opex_percentile>=0.03),
			# ,data=FERC_Data,subset=(GT==1 & outlier_flag==0 & real_opex_percentile<=0.97 & real_opex_percentile>=0.03))
			
			# Collect all of the above filters into one column
			consolidated_regression_filter = case_when(
				prime_mover == 'CC' ~ is_safe_cc,
				prime_mover == 'GT' ~ is_safe_gt,
				prime_mover == 'ST' ~ is_safe_st,
				T ~ as.logical(NA_real_)
			)
		)
}

check_are_columns_present <- function(X){
	all(c(fixed_cols, variable_cols, start_cols, 'prime_mover') %in% colnames(X))
}

get_variables_with_variance <- function(X){
	sapply(X, var) %>%
		enframe('variable', 'variance') %>%
		filter(!is.na(variance), variance > 0) %>%
		pull(variable)
}

define_formulas <- function(X){
	# This can be redefined later- the important thing is that it returns a 
	# tibble, mapping a prime_mover to a (string) formula.
	# Currently, it just groups by prime_mover, pulls any variable with variance,
	# and concatenates it into a formula, predicting real_opex 
	# without an intercept.
	
	consolidated_variables <- c(fixed_cols, variable_cols, start_cols)
	
	X %>%
		select(prime_mover, all_of(consolidated_variables)) %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		mutate(
			variables = map(data, get_variables_with_variance),
			variables_concat = map_chr(variables, paste, collapse = ' + '),
			formula = str_c('real_opex ~ 0 + ', variables_concat)
		) %>%
		select(prime_mover, formula)
}

get_coefficients <- function(X, Formulas){
	# Nest the input data around prime_mover; 
	# join to table mapping prime_mover to formula.
	# Fit linear model taking advantage of the fact that lm() will assume that the
	# first column selected (real_opex here) is the dependent variable;
	# Extract coefficients
	X %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		inner_join(Formulas, by = 'prime_mover') %>%
		mutate(
			lm_fit = map2(formula, data, ~lm(formula = .x, data = .y)),
			coefficients = map(lm_fit, 'coefficients'),
			coefficients = map(coefficients, as.data.frame),
			coefficients = map(coefficients, rownames_to_column, var = 'variable'),
		) %>%
		select(prime_mover, coefficients) %>%
		unnest(coefficients) %>%
		rename(coefficient = `.x[[i]]`)
}

#### Run script ####
variables_to_select <- unique(ChosenCoefficients$variable)

CleanedDataBySubplant <-
	DataBySubplant %>%
	create_independent_variables %>%
	create_consolidated_regression_filter %>%
	filter(consolidated_regression_filter)

# Verify the logic using full data

SummedForVerification <-
	CleanedDataBySubplant %>%
	inner_join(MapCleanedDataBySublantToClusters, by = 'rowid') %>%
	select(rowid, cls, prime_mover, all_of(variables_to_select)) %>%
	gather(variable, value, -rowid, -cls, -prime_mover) %>%
	inner_join(ChosenCoefficients, by = c('prime_mover', 'variable', 'cls')) %>%
	mutate(value_x_coefficient = value * coefficient) %>%
	group_by(rowid, cls, prime_mover, category) %>%
	summarize(summed_value_x_coefficient = sum(value_x_coefficient)) %>%
	ungroup %>%
	spread(category, summed_value_x_coefficient) %>%
	mutate_at(c('fixed', 'start', 'variable'), replace_na, 0.0)

CleanedDataBySubplant %>%
	select(rowid, capacity_mw, gross_generation_mwh, generator_starts) %>%
	inner_join(SummedForVerification) %>%
	mutate(
			fom = fixed / (capacity_mw * 1000),
			vom = variable / gross_generation_mwh,
			som = start / (capacity_mw * generator_starts * 1000),
			# == fitted_real_opex
			calculated_real_opex = (fom * capacity_mw * 1000) +
				(vom * gross_generation_mwh) +
				(som * generator_starts * capacity_mw * 1000)
		) %>%
	select(rowid, vom, fom, som) %>%
	inner_join
	print
	inner_join(FittedValues) %>%
	mutate(is_same = calculated_real_opex == fitted_values) %>%
	count(prime_mover, cls, is_same)
#	
	



CleanedHistoricalData <-
	HistoricalData %>%
	create_independent_variables

# check_are_columns_present(CleanedDataBySubplant)

# By cluster, join data to coefficients


TempLong <-
	MapHistoricalToClusters %>%
		unnest(c(rowid, cls)) %>%
		inner_join(CleanedHistoricalData, by = c("prime_mover", "rowid")) %>% 
		select(prime_mover, rowid, cls, all_of(variables_to_select)) %>%
		gather(variable, value, -rowid, -prime_mover, -cls) %>%
		arrange(rowid, variable)

TempJoined <-
	TempLong %>%
		# filter(chunk_num == 1L) %>%
		inner_join(ChosenCoefficients, by = c('prime_mover', 'cls', 'variable')) %>%
		mutate(value_times_coefficient = value * coefficient)

TempJoined %>%
	group_by(rowid, formula, category) %>%
	summarize(summed_value_times_coefficient = sum(value_times_coefficient)) %>%
	ungroup %>%
	spread(category, summed_value_times_coefficient)
#



	MapHistoricalToClusters %>%
		unnest(c(rowid, cls)) %>%
		inner_join(MapToChunk, by = c('prime_mover', 'cls'))
	
		# filter(chunk == )
		print
		filter(my_split == my_split_var) %>%
		gather(variable, value, -rowid, -prime_mover, -cls, -my_split) %>%
		inner_join(AllPossibleCoefficients, by = c('prime_mover', 'cls', 'variable')) %>%
		mutate(value_times_coefficient = value * coefficient) %>%
		group_by(prime_mover, cls, pull_size, formula, category) %>%
		summarize(summed_value_times_coefficient = sum(value_times_coefficient)) %>%
		ungroup

ArithmaticPerClusterOthers
	
		
HistoricalValuesAndCoefsCC <- 
	join_clustered_historical_data_to_formulas(prime_mover_var = 'CC')
HistoricalValuesAndCoefsGT <- 
	join_clustered_historical_data_to_formulas(prime_mover_var = 'GT')
HistoricalValuesAndCoefsST <- 
	join_clustered_historical_data_to_formulas(prime_mover_var = 'ST')


JoinmeGT <-
	MapHistoricalToClusters %>%
		filter(prime_mover == 'GT') %>%
		unnest(c(rowid, cls)) %>%
		left_join(CleanedHistoricalData, by = c("prime_mover", "rowid")) %>%
		select(rowid, prime_mover, cls, all_of(variables_to_select)) %>%
		gather(variable, value, -rowid, -prime_mover, -cls) %>%
		inner_join(AllPossibleCoefficients, by = c('prime_mover', 'cls', 'variable'))
JoinmeST <-
	MapHistoricalToClusters %>%
		filter(prime_mover == 'ST') %>%
		unnest(c(rowid, cls)) %>%
		left_join(CleanedHistoricalData, by = c("prime_mover", "rowid")) %>%
		select(rowid, prime_mover, cls, all_of(variables_to_select)) %>%
		gather(variable, value, -rowid, -prime_mover, -cls) %>%
		inner_join(AllPossibleCoefficients, by = c('prime_mover', 'cls', 'variable'))

#



Formulas <- define_formulas(CleanedDataBySubplant)
Coefficients <- get_coefficients(CleanedDataBySubplant, Formulas)

SummedDataByVariableType <-
	CleanedDataBySubplant %>%
	# rowid serves as UID but we need prime_mover to join with coefficients
	select(rowid, prime_mover, all_of(variable_cols), 
				 all_of(fixed_cols), all_of(start_cols)
	) %>%
	gather(variable, value, -rowid, -prime_mover) %>%
	arrange(rowid, variable) %>%
	inner_join(Coefficients, by = c('prime_mover', 'variable')) %>%
	mutate(value_times_coefficient = value * coefficient) %>%
	inner_join(MapVariableToVariableType, by = 'variable') %>%
	group_by(rowid, variable_type) %>%
	summarize(sum = sum(value_times_coefficient)) %>%
	ungroup %>%
	spread(variable_type, sum)

Coefficients %>%
	filter(is.na(coefficient))

CapacityGeneratorStartsGrossGeneration <-
	CleanedDataBySubplant %>%
	select(rowid, capacity_mw, generator_starts, gross_generation_mwh)

Result <-
	SummedDataByVariableType %>%
	inner_join(CapacityGeneratorStartsGrossGeneration, by = c('rowid')) %>%
	mutate(
		fom = fixed / (capacity_mw * 1000),
		vom = variable / gross_generation_mwh,
		som = start / (capacity_mw * generator_starts * 1000),
		# == fitted_real_opex
		calculated_real_opex = (fom * capacity_mw * 1000) + 
			(vom * gross_generation_mwh) + 
			(som * generator_starts * capacity_mw * 1000)
	)

Result %>%
	skim


FitRealOpex <-
	CleanedDataBySubplant	%>%
	group_by(prime_mover) %>%
	nest %>%
	ungroup %>%
	inner_join(Formulas, by = 'prime_mover') %>%
	mutate(
		lm_fit = map2(formula, data, ~lm(formula = .x, data = .y)),
		fit_real_opex = map(lm_fit, 'fitted.values'),
		rowid = map(data, 'rowid')
	) %>%
	select(rowid, fit_real_opex) %>%
	unnest(everything())

Result %>%
	select(rowid, calculated_real_opex) %>%
	full_join(FitRealOpex) %>%
	skim
# filter(!is.na(calculated_real_opex)) %>%

CleanedDataBySubplant %>%
	select(rowid, prime_mover, all_of(variable_cols), all_of(fixed_cols), 
				 all_of(start_cols))

write_csv(CleanedDataBySubplant, 'clean_data/cleaned_data_by_subplant.csv')
write_csv(CleanedHistoricalData, 'clean_data/cleaned_historical_data.csv')
write_csv(LongVariableKey, 'clean_data/long_variable_key.csv')
