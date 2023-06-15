# Final work with coefficients
# 1. get all the regression variables ready; get PCA scores; weight PCA scores;
# put into cluster
# 2. Run final metric transformations

library(tidyverse)
library(skimr)
library(conflicted)
# library(broom)
library(arrow)
library(lubridate)
library(flexclust)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')
HistoricRaw <- read_parquet('input_data/historic_data_gen_level.parquet')
NestedCoefficients <- readRDS('clean_data/nested_coefficients.RDS')
ClusteredHist <- readRDS('clean_data/clustered_hist.RDS')

TempCoefficients <-
	NestedCoefficients %>%
		filter(num_clusters == 2, cluster == 1) %>%
		unnest(coefficients) %>%
		select(prime_mover, measure, estimate) %>%
		spread(measure, estimate) %>%
		mutate_if(is.numeric, replace_na, 0.0)
#
# Merge coefficients with historic data
# Coefficients <-
# 	Mods %>%
# 		mutate(
# 			coefficients = map(lm_fit, 'coefficients'),
# 			coefficients = map(coefficients, as.data.frame),
# 			coefficients = map(coefficients, rownames_to_column),
# 			) %>%
# 		select(prime_mover, coefficients) %>%
# 		unnest(coefficients) %>%
# 		rename('variable' = rowname, 'value' = 3) %>%
# 		spread(variable, value)
NestedCoefficients %>%
	unnest(coefficients) %>%
	distinct(measure) %>%
	arrange(measure) %>%
	pull

# python_inputs_data_hist <- 
	HistoricRaw %>%
		inner_join(TempCoefficients, by = 'prime_mover') %>%
		# Prelim variables
		mutate(
			capacity_adj = wage_scale * capacity_mw,
			pulverized_coal_fixed_adj = pulverized_coal_tech * capacity_adj,
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
			(gas_pollution_fixed_adj * natural_gas_fraction * pollution_control_costs_per_kw * wage_scale)),
			# (gas_pollution_fixed_adj * fuel_frac_natural_gas * pollution_control_costs_per_kW * wage_scale)),
		real_opex_per_kW_start = starts_adj +  (gas_starts_adj * natural_gas_fraction) + 
		# real_opex_per_kW_start = starts_adj +  (gas_starts_adj * fuel_frac_natural_gas) + 
			(oil_starts_adj * petroleum_fraction),
			# (oil_starts_adj * fuel_frac_petroleum),
		real_fixed_opex_per_kW_age_coeff = age_obs_fixed_adj * wage_scale
	)

	
	
str1 <- "	
	(capacity_adj * wage_scale) + 
		(gas_fixed_adj * fuel_frac_natural_gas * wage_scale) + 
		(oil_fixed_adj * fuel_frac_petroleum * wage_scale) +
		(CHP_fixed_adj * chp * wage_scale) +
		(pollution_fixed_adj * pollution_control_costs_per_kW * wage_scale) +
		(pulverized_coal_fixed_adj * pulverized_coal * wage_scale) +
		(duct_burners_fixed_adj * duct_burners * wage_scale) +
		(supercritical_fixed_adj * supercritical * wage_scale) +
		(age_fixed_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
		(oil_age_fixed_adj * diff_age_and_avg_plant_prime_fuel * fuel_frac_petroleum * wage_scale) +
		(gas_pollution_fixed_adj * fuel_frac_natural_gas * pollution_control_costs_per_kW * wage_scale)),
starts_adj +  (gas_starts_adj * fuel_frac_natural_gas) + 
	(oil_starts_adj * fuel_frac_petroleum),
age_obs_fixed_adj * wage_scale"
str2 <- "(gen_adj * wage_scale) +
      (median_CF_adj * median_CF * wage_scale ) +
      (high_median_CF_adj * high_median_CF * wage_scale ) +
      (mid_median_CF_adj * mid_median_CF * wage_scale ) +
      (low_median_CF_adj * low_median_CF * wage_scale ) +
      (oil_variable_adj * fuel_frac_petroleum * wage_scale) +
      (pollution_variable_adj * pollution_control_costs_per_kW * wage_scale) +
      (age_variable_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
      (fluidized_bed_variable_adj * fluidized_bed * wage_scale) +
      (CHP_variable_adj * chp * wage_scale) +
      (supercritical_variable_adj * supercritical * wage_scale) +
      (gas_age_variable_adj * fuel_frac_natural_gas * diff_age_and_avg_plant_prime_fuel * wage_scale) +
      (duct_burners_variable_adj * duct_burners * wage_scale) +
      (oil_age_variable_adj * fuel_frac_petroleum * diff_age_and_avg_plant_prime_fuel * wage_scale)),
    (age_obs_variable_adj * wage_scale) ) "

c(str1, str2) %>%
	enframe(name = NULL, value = 'text') %>%
	mutate(token = str_extract_all(text, '[A-Za-z0-9_]+')) %>%
	unnest(token) %>%
	distinct(token) %>%
	arrange(token) %>%
	mutate(is_in_hist = token %in% colnames(Historic),
				 is_regression_variable = token %in% variables_for_regressions,
				 is_median_cf = str_detect(token, 'median_CF')
  ) %>%
	filter(!is_in_hist & !is_regression_variable & !is_median_cf)
# fuel_frac_natural_gas

Historic$supercritical_tech
