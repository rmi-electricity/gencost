# Power Plant Characteristics
# 2_elt_specific_to_linear_regression
# 2023 April Andrew Bartnof
# Recreate Uday's synthetic variable creation, which will be fed into his
# linear models

library(conflicted)
library(skimr)
library(tidyverse)
conflict_prefer('select', 'dplyr')
conflict_prefer('filter', 'dplyr')
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')
Data <- readRDS('clean_data/Data.RDS')

#### Prepare data for modelling (aggregated variables) ####
ModellableData <-
	Data %>%
	mutate(
		capacity = operating_capacity_in_report_year * 1000,
		gas_fixed = natural_gas * capacity,
		oil_fixed = petroleum * capacity,
		other_fixed = other_gas * capacity,
		coal_fixed = coal * capacity,
		pollution_fixed = pollution_control_costs_per_kw * capacity,
		age_fixed = age_relative_to_average * capacity,
		associated_combined_heat_power_fixed = associated_combined_heat_power * capacity,
		duct_burners_fixed = duct_burners * capacity,
		bypass_heat_recovery_fixed = bypass_heat_recovery * capacity,
		solid_fuel_gasification_fixed = solid_fuel_gasification * capacity,
		carbon_capture_fixed = carbon_capture * capacity,
		fluidized_bed_tech_fixed = fluidized_bed_tech * capacity,
		pulverized_coal_tech_fixed = pulverized_coal_tech * capacity,
		stoker_tech_fixed = stoker_tech * capacity,
		other_combustion_tech_fixed = other_combustion_tech * capacity,
		subcritical_tech_fixed = subcritical_tech * capacity,
		supercritical_tech_fixed = supercritical_tech * capacity,
		ultrasupercritical_tech_fixed = ultrasupercritical_tech * capacity,
		coal_pollution_fixed = coal * pollution_control_costs_per_kw * capacity,
		coal_age_fixed = coal * age_relative_to_average * capacity,
		gas_pollution_fixed = natural_gas * pollution_control_costs_per_kw * capacity,
		gas_age_fixed = natural_gas * age_relative_to_average * capacity,
		oil_pollution_fixed = petroleum * pollution_control_costs_per_kw * capacity,
		oil_age_fixed = petroleum * age_relative_to_average * capacity,
		coal_associated_combined_heat_power_fixed = associated_combined_heat_power * coal * capacity,
		gas_associated_combined_heat_power_fixed = associated_combined_heat_power * natural_gas * capacity,
		oil_associated_combined_heat_power_fixed = associated_combined_heat_power * petroleum * capacity,
		other_associated_combined_heat_power_fixed = associated_combined_heat_power * other_gas * capacity,
		age_obs_fixed = capacity * age_obs_adj,
		cum_starts_age_obs_fixed = cum_starts * capacity * age_obs_adj,
		associated_combined_heat_power_age_obs_fixed = associated_combined_heat_power * capacity * age_obs_adj,
		duct_burners_age_obs_fixed = duct_burners * capacity * age_obs_adj,
		bypass_heat_recovery_age_obs_fixed = bypass_heat_recovery * capacity * age_obs_adj,
		solid_fuel_gasification_age_obs_fixed = solid_fuel_gasification * capacity * age_obs_adj,
		carbon_capture_age_obs_fixed = carbon_capture * capacity * age_obs_adj,
		fluidized_bed_tech_age_obs_fixed = fluidized_bed_tech * capacity * age_obs_adj,
		pulverized_coal_tech_age_obs_fixed = pulverized_coal_tech * capacity * age_obs_adj,
		stoker_tech_age_obs_fixed = stoker_tech * capacity * age_obs_adj,
		other_combustion_tech_age_obs_fixed = other_combustion_tech * capacity * age_obs_adj,
		subcritical_tech_age_obs_fixed = subcritical_tech * capacity * age_obs_adj,
		supercritical_tech_age_obs_fixed = supercritical_tech * capacity * age_obs_adj,
		ultrasupercritical_tech_age_obs_fixed = ultrasupercritical_tech * capacity * age_obs_adj,
		coal_age_obs_fixed = coal * capacity * age_obs_adj,
		gas_age_obs_fixed = natural_gas * capacity * age_obs_adj,
		oil_age_obs_fixed = petroleum * capacity * age_obs_adj,
		other_age_obs_fixed = other_gas * capacity * age_obs_adj
	) %>%
	mutate(
		capacity_adj = wage_scale * capacity,
		starts_adj = generator_starts * capacity_adj,
		gas_starts_adj = natural_gas * starts_adj,
		oil_starts_adj = petroleum * starts_adj,
		other_starts_adj = other_gas * starts_adj,
		coal_starts_adj = coal * starts_adj,
		gas_fixed_adj = natural_gas * capacity_adj,
		oil_fixed_adj = petroleum * capacity_adj,
		other_fixed_adj = other_gas * capacity_adj,
		coal_fixed_adj = coal * capacity_adj,
		high_median_CF_fixed_adj = high_median_CF * capacity_adj,
		mid_median_CF_fixed_adj = mid_median_CF * capacity_adj,
		low_median_CF_fixed_adj = low_median_CF * capacity_adj,
		median_CF_fixed_adj = median_CF * capacity_adj,
		pollution_fixed_adj = real_pollution_control_costs_per_kw * capacity_adj,
		age_fixed_adj = age_relative_to_average * capacity_adj,
		age_obs_fixed_adj = age_of_observation * capacity_adj,
		chp_fixed_adj = associated_combined_heat_power * capacity_adj,
		duct_burners_fixed_adj = duct_burners * capacity_adj,
		bypass_heat_recovery_fixed_adj = bypass_heat_recovery * capacity_adj,
		gasification_fixed_adj = solid_fuel_gasification * capacity_adj,
		ccs_fixed_adj = carbon_capture * capacity_adj,
		fluidized_bed_fixed_adj = fluidized_bed_tech * capacity_adj,
		pulverized_coal_fixed_adj = pulverized_coal_tech * capacity_adj,
		stoker_fixed_adj = stoker_tech * capacity_adj,
		other_comb_fixed_adj = other_combustion_tech * capacity_adj,
		subcritical_fixed_adj = subcritical_tech * capacity_adj,
		supercritical_fixed_adj = supercritical_tech * capacity_adj,
		ultrasupercritical_fixed_adj = ultrasupercritical_tech * capacity_adj,
		coal_pollution_fixed_adj = coal * real_pollution_control_costs_per_kw * capacity_adj,
		coal_age_fixed_adj = coal * age_relative_to_average * capacity_adj,
		gas_pollution_fixed_adj = natural_gas * real_pollution_control_costs_per_kw * capacity_adj,
		gas_age_fixed_adj = natural_gas * age_relative_to_average * capacity_adj,
		oil_pollution_fixed_adj = petroleum * real_pollution_control_costs_per_kw * capacity_adj,
		oil_age_fixed_adj = petroleum * age_relative_to_average * capacity_adj,
		gen = gross_cf * operating_capacity_in_report_year * ifelse(report_year %% 4 ==0,8784,8760),
		gen_adj = wage_scale * gen,
		high_median_CF_adj = high_median_CF * gen_adj,
		mid_median_CF_adj = mid_median_CF * gen_adj,
		low_median_CF_adj = low_median_CF * gen_adj,
		median_CF_adj = median_CF * gen_adj,
		gas_variable_adj = natural_gas * gen_adj,
		oil_variable_adj = petroleum * gen_adj,
		other_variable_adj = other_gas * gen_adj,
		coal_variable_adj = coal * gen_adj,
		pollution_variable_adj = real_pollution_control_costs_per_kw * gen_adj,
		age_variable_adj = age_relative_to_average * gen_adj,
		age_obs_variable_adj = age_of_observation * gen_adj,
		CHP_variable_adj = associated_combined_heat_power * gen_adj,
		duct_burners_variable_adj = duct_burners * gen_adj,
		bypass_heat_recovery_variable_adj = bypass_heat_recovery * gen_adj,
		gasification_variable_adj = solid_fuel_gasification * gen_adj,
		ccs_variable_adj = carbon_capture * gen_adj,
		fluidized_bed_variable_adj = fluidized_bed_tech * gen_adj,
		pulverized_coal_variable_adj = pulverized_coal_tech * gen_adj,
		stoker_variable_adj = stoker_tech * gen_adj,
		other_comb_variable_adj = other_combustion_tech * gen_adj,
		subcritical_variable_adj = subcritical_tech * gen_adj,
		supercritical_variable_adj = supercritical_tech * gen_adj,
		ultrasupercritical_variable_adj = ultrasupercritical_tech * gen_adj,
		coal_pollution_variable_adj = coal * real_pollution_control_costs_per_kw * gen_adj,
		coal_age_variable_adj = coal * age_relative_to_average * gen_adj,
		gas_pollution_variable_adj = natural_gas * real_pollution_control_costs_per_kw * gen_adj,
		gas_age_variable_adj = natural_gas * age_relative_to_average * gen_adj,
		oil_pollution_variable_adj = petroleum * real_pollution_control_costs_per_kw * gen_adj,
		oil_age_variable_adj = petroleum * age_relative_to_average * gen_adj
	) %>%
	rowid_to_column %>%
	mutate(rowid = as.character(rowid))

# write_rds(ModellableData, file = 'clean_data/modellable_data.RDS')

#### Subsets for linear models ####	
STopex <-
	ModellableData %>%
		filter(st == 1, gross_cf <= 1.1, outlier_flag == 0)
write_rds(STopex, 'clean_data/stopex.RDS')

CCopex <- 
	ModellableData %>%
	filter(cc == 1,
					coal == 0, 
					outlier_flag == 0,
					real_opex_percentile <= 0.97,
					real_opex_percentile >= 0.03
	)
write_rds(CCopex, file = 'clean_data/ccopex.RDS')

GTopex <-
	ModellableData %>%
		filter(gt == 1, outlier_flag==0, 
					 real_opex_percentile<=0.97, real_opex_percentile >=0.03)
write_rds(GTopex, file = 'clean_data/gtopex.RDS')
