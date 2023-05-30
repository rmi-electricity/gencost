# Final work with coefficients

library(tidyverse)
library(skimr)
library(conflicted)
library(broom)
library(arrow)
library(lubridate)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

ClusteredData <- read_csv('clean_data/clustered_data.csv', col_types = c(
	prime_mover = 'c', plant_id_eia = 'f', cluster = 'f', 
	consolidated_regression_filter = 'l', .default = 'd'))

Data <- read_csv('clean_data/data.csv', col_types = c(
	prime_mover = 'c', plant_id_eia = 'f',
	consolidated_regression_filter = 'l', .default = 'd'))

Mods <- readRDS('clean_data/mods.RDS')

Historic <- read_parquet('input_data/historical_data_gen_level_0523.parquet')

# Merge coefficients with historic data
Coefficients <-
	Mods %>%
		mutate(
			coefficients = map(lm_fit, 'coefficients'),
			coefficients = map(coefficients, as.data.frame),
			coefficients = map(coefficients, rownames_to_column),
			) %>%
		select(prime_mover, coefficients) %>%
		unnest(coefficients) %>%
		rename('variable' = rowname, 'value' = 3) %>%
		spread(variable, value)

Coefficients %>%
	skim

# NB: what to do about missing coefficients?
# python_inputs_data <- 
Coefficients %>% colnames %>% sort
Historic %>% select(contains('combined'))
# recreate variables on my own:

	Historic %>%
	inner_join(Coefficients, by = 'prime_mover') %>%
	mutate(
		real_fixed_opex_per_kW_no_starts_est = (
				(capacity_adj * wage_scale) +
					
					# TODO Figure out what to do with these
		# 		(median_CF_fixed_adj * median_CF * wage_scale ) +
		# 		(high_median_CF_fixed_adj * high_median_CF * wage_scale ) +
		# 		(mid_median_CF_fixed_adj * mid_median_CF * wage_scale ) +
		# 		(low_median_CF_fixed_adj * low_median_CF * wage_scale ) +
			
		# gas_fixed_adj is a lm coefficient; wage_scale is in historic; fuel_frac_natural_gas is something i don't have (supposed to be called now natural_gas_fraction?)
				# (gas_fixed_adj * fuel_frac_natural_gas * wage_scale)))

		# oil_fixed_adj is from the lm; wage_scale is from the historic; fuel_frac_petroleum should now be called petroleum_fraction and it is missing
				# (oil_fixed_adj * fuel_frac_petroleum * wage_scale) +
		
		# CHP_fixed_adj = CHP * capacity_adj, and CHP is now associated_combined_heat_power; i have these variables
		# wage_scale comes from hist. if chp is also assoc_combined_heat_power, as is said in the spreadsheet, then we're squaring it??
		# this would be:
		# (associated_combined_heat_power * capacity_adj) * associated_combined_heat_power * wage_scale
				# (CHP_fixed_adj * chp * wage_scale)))

		# pollution_fixed_adj is     pollution_fixed_adj = real_pollution_control_costs_per_kW * capacity_adj,
		# but we're missing real_pollution_control_costs_per_kW (upper or lower case)
		
		# 		(pollution_fixed_adj * pollution_control_costs_per_kW * wage_scale) +
		# 		(pulverized_coal_fixed_adj * pulverized_coal * wage_scale) +
		# 		(duct_burners_fixed_adj * duct_burners * wage_scale) +
		# 		(supercritical_fixed_adj * supercritical * wage_scale) +
		# 		(age_fixed_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
		# 		(oil_age_fixed_adj * diff_age_and_avg_plant_prime_fuel * fuel_frac_petroleum * wage_scale) +
		# 		(gas_age_fixed_adj * diff_age_and_avg_plant_prime_fuel * fuel_frac_natural_gas * wage_scale) +
		# 		(gas_pollution_fixed_adj * fuel_frac_natural_gas * pollution_control_costs_per_kW * wage_scale)),
		# 	real_opex_per_kW_start = starts_adj + 
		# 		(gas_starts_adj * fuel_frac_natural_gas) + 
		# 		(oil_starts_adj * fuel_frac_petroleum),
		# 	real_fixed_opex_per_kW_age_coeff = age_obs_fixed_adj * wage_scale
		# )
		)
