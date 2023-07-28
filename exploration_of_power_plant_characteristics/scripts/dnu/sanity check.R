library(tidyverse)
library(skimr)
library(conflicted)
# library(broom)
library(arrow)
library(lubridate)
library(flexclust)
library(lavaan)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

perform_final_transformations <- function(X){
	X %>%
		# Prelim variables
		mutate(
			capacity_adj = wage_scale * capacity_mw,
			pulverized_coal_fixed_adj = pulverized_coal_tech * capacity_adj,
			CHP_variable_adj = associated_combined_heat_power * gen_adj,
			duct_burners_variable_adj = duct_burners * gen_adj,
			oil_age_variable_adj = petroleum_fraction * age_relative_to_prime_avg * gen_adj,
		) %>%
		mutate(
			real_fixed_opex_per_kW_no_starts_est = ( 
				(capacity_adj * wage_scale) + 
					# (median_CF_fixed_adj * median_CF * wage_scale ) +
					# (high_median_CF_fixed_adj * high_median_CF * wage_scale ) +
					# (mid_median_CF_fixed_adj * mid_median_CF * wage_scale ) +
					# (low_median_CF_fixed_adj * low_median_CF * wage_scale ) +
					(gas_fixed_adj * natural_gas_fraction * wage_scale) + 
					# (gas_fixed_adj * fuel_frac_natural_gas * wage_scale) + 
					(oil_fixed_adj * petroleum_fraction * wage_scale) +
					# (oil_fixed_adj * fuel_frac_petroleum * wage_scale) +
					(CHP_fixed_adj * associated_combined_heat_power * wage_scale) +
					# (CHP_fixed_adj * chp * wage_scale) +
					(pollution_fixed_adj * pollution_control_costs_per_kw * wage_scale) +
					# (pollution_fixed_adj * pollution_control_costs_per_kW * wage_scale) +
					(pulverized_coal_fixed_adj * pulverized_coal_tech * wage_scale) +
					# (pulverized_coal_fixed_adj * pulverized_coal * wage_scale) +
					(duct_burners_fixed_adj * duct_burners * wage_scale) +
					(supercritical_fixed_adj * supercritical_tech * wage_scale) +
					# (supercritical_fixed_adj * supercritical * wage_scale) +
					(age_fixed_adj * age_relative_to_prime_avg * wage_scale) +
					# (age_fixed_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
					(oil_age_fixed_adj * age_relative_to_prime_avg * petroleum_fraction * wage_scale) +
					# (oil_age_fixed_adj * diff_age_and_avg_plant_prime_fuel * fuel_frac_petroleum * wage_scale) +
					(gas_age_fixed_adj * age_relative_to_prime_avg * natural_gas_fraction * wage_scale) +
					# (gas_age_fixed_adj * diff_age_and_avg_plant_prime_fuel * fuel_frac_natural_gas * wage_scale) +
					(gas_pollution_fixed_adj * natural_gas_fraction * pollution_control_costs_per_kw * wage_scale)),
			# (gas_pollution_fixed_adj * fuel_frac_natural_gas * pollution_control_costs_per_kW * wage_scale)),
			real_opex_per_kW_start = starts_adj +  (gas_starts_adj * natural_gas_fraction) + 
				# real_opex_per_kW_start = starts_adj +  (gas_starts_adj * fuel_frac_natural_gas) + 
				(oil_starts_adj * petroleum_fraction),
			# (oil_starts_adj * fuel_frac_petroleum),
			real_fixed_opex_per_kW_age_coeff = age_obs_fixed_adj * wage_scale
		) %>%
		# Calculate estimated real variable costs opex, again breaking out coefficients dependent on age of observation
		# only for historical cost estimation
		mutate(real_variable_opex_per_MWh_est = (
			(gen_adj * wage_scale) +
				# (median_CF_adj * median_CF * wage_scale ) +
				# (high_median_CF_adj * high_median_CF * wage_scale ) +
				# (mid_median_CF_adj * mid_median_CF * wage_scale ) +
				# (low_median_CF_adj * low_median_CF * wage_scale ) +
				(oil_variable_adj * petroleum_fraction * wage_scale) +
				# (oil_variable_adj * fuel_frac_petroleum * wage_scale) +
				(pollution_variable_adj * pollution_control_costs_per_kw * wage_scale) +
				# (pollution_variable_adj * pollution_control_costs_per_kW * wage_scale) +
				(age_variable_adj * age_relative_to_prime_avg * wage_scale) +
				# (age_variable_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
				(fluidized_bed_variable_adj * fluidized_bed_tech * wage_scale) +
				# (fluidized_bed_variable_adj * fluidized_bed * wage_scale) +
				(CHP_variable_adj * associated_combined_heat_power * wage_scale) +
				# (CHP_variable_adj * chp * wage_scale) +
				(supercritical_variable_adj * supercritical_tech * wage_scale) +
				# (supercritical_variable_adj * supercritical * wage_scale) +
				(gas_age_variable_adj * natural_gas_fraction * age_relative_to_prime_avg * wage_scale) +
				# (gas_age_variable_adj * fuel_frac_natural_gas * diff_age_and_avg_plant_prime_fuel * wage_scale) +
				(duct_burners_variable_adj * duct_burners * wage_scale) +
				(oil_age_variable_adj * petroleum_fraction * age_relative_to_prime_avg * wage_scale)),
			# (oil_age_variable_adj * fuel_frac_petroleum * diff_age_and_avg_plant_prime_fuel * wage_scale)),
			real_variable_opex_per_MWh_age_coeff = (age_obs_variable_adj * wage_scale)
		)
}

# 1. read raw subplant data
# 2. apply coefficients WHERE num_clusters == 1
# 3. run yesterday's sanity check math and make sure the numbers are commensurate

DataRaw <- read_parquet('input_data/data_by_subplant.parquet') %>%
	rowid_to_column
NestedCoefficients <- readRDS('clean_data/nested_coefficients.RDS')

Coefficients <-
	NestedCoefficients %>%
		filter(num_clusters == 1L) %>%
		# mutate(real_opex_fitted = map(lm_fit, 'fitted.values')) %>%
		unnest(c(coefficients)) %>%
		select(prime_mover, measure, estimate) %>%
		spread(measure, estimate) %>%
		mutate_if(is.numeric, replace_na, 0.0)
#
Coefficients

JoinedData <-
	DataRaw %>%
		select(-gross_cf) %>%
		inner_join(Coefficients, by = 'prime_mover')

TransformedData <- perform_final_transformations(JoinedData)

key_output_variables <-
	c('real_fixed_opex_per_kW_no_starts_est',
	'real_variable_opex_per_MWh_est',
	'real_opex_per_kW_start')

TransformedData %>%
	select(all_of(key_output_variables)) %>%
	skim


DataWithCalculatedRealOpex <-
	TransformedData %>%
		mutate(
		calculated_real_opex = 
			(real_fixed_opex_per_kW_no_starts_est * capacity_mw * 1000) +
			(real_variable_opex_per_MWh_est * gross_generation_mwh) +
			(real_opex_per_kW_start * capacity_mw * 1000 * generator_starts)
		)

sort(colnames(Coefficients))

JoinmeMods <-
	# Built in regressions.R
	ModsFit %>%
		filter(num_clusters == 1L)

RealOpexFit <-
	Data %>%
		group_by(prime_mover) %>%
		nest %>%
		ungroup %>%
		left_join(JoinmeMods, by = 'prime_mover') %>%
		mutate(real_opex_fit = map2(lm_fit, data, predict.lm)) %>%
		unnest(cols = c(data, real_opex_fit)) %>%
		select(rowid, real_opex_fit)

DataWithCalculatedRealOpex %>%
	select(prime_mover, rowid, calculated_real_opex, real_opex) %>%
	inner_join(RealOpexFit) %>%
	sample_n(10)

JoinmeData <-
	DataWithCalculatedRealOpex %>%
		group_by(prime_mover) %>%
		nest

NestedCoefficients %>%
	filter(num_clusters == 1L) %>%
	select(prime_mover, lm_fit) %>%
	inner_join(JoinmeData, by = 'prime_mover') %>%
	mutate(
		real_opex_fit = map2(lm_fit, data, predict.lm)
	) %>%
	select(-lm_fit) %>%
	unnest(c(data, real_opex_fit)) %>%
	mutate(residuals = real_opex_fit - real_opex) %>%
	summarize(
		median_real_opex = median(real_opex, na.rm = T),
		median_residuals = median(residuals, na.rm = T)
	)
	# select(calculated_real_opex, real_opex_fit) %>%

DataWithCalculatedRealOpex	%>%
	skim(calculated_real_opex)



(lm(chickwts))
