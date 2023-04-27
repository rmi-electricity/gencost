# data_for_pf_subplants.parquet imputation project
# 1. ELT
# Andrew Bartnof, RMI March 2023

library(tidyverse)
library(arrow)
library(skimr)
library(conflicted)
library(readxl)
conflict_prefer("map", "purrr")
conflict_prefer("filter", "dplyr")
set.seed(1)

# load data
# select only variables that we want to model
# rename columns to legacy names
setwd('~/Documents/rmi/power_plant_characteristics/')
RawData <- read_parquet('input_data/data_for_pf_subplants.parquet')
write_rds(RawData, file = 'clean_data/RawData.RDS')


#### Collect the right-hand variables from the upstream synthetic variables ####
pull_variables <- function(raw_text){
	str_replace_all(raw_text, "[\r\n\t]" , "") %>%
		str_split(pattern = ',') %>%
		enframe(name = NULL) %>%
		unnest(value) %>%
		separate('value', c('left', 'right'), sep = '=') %>%
		mutate(left = str_trim(left),
					 right_variables = str_split(right, '\\s+')) %>%
		unnest(right_variables) %>%
		mutate(right_variables = str_trim(right_variables)) %>%
		filter(str_length(right_variables) > 0, right_variables != '*', 
					 !str_detect(right_variables, '[0-9]+')
		) %>%
		select(left_hand_variables = left, right_hand_variables = right_variables)
}


# line 1432
raw_text <- "
		capacity = operating_capacity_in_report_year * 1000,
		gas_fixed = natural_gas * capacity,
		oil_fixed = petroleum * capacity,
		other_fixed = other_gas * capacity,
		coal_fixed = coal * capacity,
		pollution_fixed = pollution_control_costs_per_kW * capacity,
		age_fixed = age_relative_to_average * capacity,
		CHP_fixed = CHP * capacity,
		duct_burners_fixed = duct_burners * capacity,
		bypass_hrsg_fixed = bypass_hrsg * capacity,
		gasification_fixed = gasification * capacity,
		ccs_fixed = ccs * capacity,
		fluidized_bed_fixed = fluidized_bed * capacity,
		pulverized_coal_fixed = pulverized_coal * capacity,
		stoker_fixed = stoker * capacity,
		other_comb_fixed = other_comb * capacity,
		subcritical_fixed = subcritical * capacity,
		supercritical_fixed = supercritical * capacity,
		ultrasupercritical_fixed = ultrasupercritical * capacity,
		coal_pollution_fixed = coal * pollution_control_costs_per_kW * capacity,
		coal_age_fixed = coal * age_relative_to_average * capacity,
		gas_pollution_fixed = natural_gas * pollution_control_costs_per_kW * capacity,
		gas_age_fixed = natural_gas * age_relative_to_average * capacity,
		oil_pollution_fixed = petroleum * pollution_control_costs_per_kW * capacity,
		oil_age_fixed = petroleum * age_relative_to_average * capacity,
		coal_CHP_fixed = CHP * coal * capacity,
		gas_CHP_fixed = CHP * natural_gas * capacity,
		oil_CHP_fixed = CHP * petroleum * capacity,
		other_CHP_fixed = CHP * other_gas * capacity,
		age_obs_fixed = capacity * age_obs_adj,
		cum_starts_age_obs_fixed = cum_starts * capacity * age_obs_adj,
		CHP_age_obs_fixed = CHP * capacity * age_obs_adj,
		duct_burners_age_obs_fixed = duct_burners * capacity * age_obs_adj,
		bypass_hrsg_age_obs_fixed = bypass_hrsg * capacity * age_obs_adj,
		gasification_age_obs_fixed = gasification * capacity * age_obs_adj,
		ccs_age_obs_fixed = ccs * capacity * age_obs_adj,
		fluidized_bed_age_obs_fixed = fluidized_bed * capacity * age_obs_adj,
		pulverized_coal_age_obs_fixed = pulverized_coal * capacity * age_obs_adj,
		stoker_age_obs_fixed = stoker * capacity * age_obs_adj,
		other_comb_age_obs_fixed = other_comb * capacity * age_obs_adj,
		subcritical_age_obs_fixed = subcritical * capacity * age_obs_adj,
		supercritical_age_obs_fixed = supercritical * capacity * age_obs_adj,
		ultrasupercritical_age_obs_fixed = ultrasupercritical * capacity * age_obs_adj,
		coal_age_obs_fixed = coal * capacity * age_obs_adj,
		gas_age_obs_fixed = natural_gas * capacity * age_obs_adj,
		oil_age_obs_fixed = petroleum * capacity * age_obs_adj,
		other_age_obs_fixed = other_gas * capacity * age_obs_adj
"

# line 1485
raw_text2 <- "
		capacity_adj = wage_scale * capacity,
		starts_adj = starts * capacity_adj,
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
		pollution_fixed_adj = real_pollution_control_costs_per_kW * capacity_adj,
		age_fixed_adj = age_relative_to_average * capacity_adj,
		age_obs_fixed_adj = age_of_observation * capacity_adj,
		CHP_fixed_adj = CHP * capacity_adj,
		duct_burners_fixed_adj = duct_burners * capacity_adj,
		bypass_hrsg_fixed_adj = bypass_hrsg * capacity_adj,
		gasification_fixed_adj = gasification * capacity_adj,
		ccs_fixed_adj = ccs * capacity_adj,
		fluidized_bed_fixed_adj = fluidized_bed * capacity_adj,
		pulverized_coal_fixed_adj = pulverized_coal * capacity_adj,
		stoker_fixed_adj = stoker * capacity_adj,
		other_comb_fixed_adj = other_comb * capacity_adj,
		subcritical_fixed_adj = subcritical * capacity_adj,
		supercritical_fixed_adj = supercritical * capacity_adj,
		ultrasupercritical_fixed_adj = ultrasupercritical * capacity_adj,
		coal_pollution_fixed_adj = coal * real_pollution_control_costs_per_kW * capacity_adj,
		coal_age_fixed_adj = coal * age_relative_to_average * capacity_adj,
		gas_pollution_fixed_adj = natural_gas * real_pollution_control_costs_per_kW * capacity_adj,
		gas_age_fixed_adj = natural_gas * age_relative_to_average * capacity_adj,
		oil_pollution_fixed_adj = petroleum * real_pollution_control_costs_per_kW * capacity_adj,
		oil_age_fixed_adj = petroleum * age_relative_to_average * capacity_adj,
		gen = FERC_CF * operating_capacity_in_report_year * report_year,
		gen_adj = wage_scale * gen,
		high_median_CF_adj = high_median_CF * gen_adj,
		mid_median_CF_adj = mid_median_CF * gen_adj,
		low_median_CF_adj = low_median_CF * gen_adj,
		median_CF_adj = median_CF * gen_adj,
		gas_variable_adj = natural_gas * gen_adj,
		oil_variable_adj = petroleum * gen_adj,
		other_variable_adj = other_gas * gen_adj,
		coal_variable_adj = coal * gen_adj,
		pollution_variable_adj = real_pollution_control_costs_per_kW * gen_adj,
		age_variable_adj = age_relative_to_average * gen_adj,
		age_obs_variable_adj = age_of_observation * gen_adj,
		CHP_variable_adj = CHP * gen_adj,
		duct_burners_variable_adj = duct_burners * gen_adj,
		bypass_hrsg_variable_adj = bypass_hrsg * gen_adj,
		gasification_variable_adj = gasification * gen_adj,
		ccs_variable_adj = ccs * gen_adj,
		fluidized_bed_variable_adj = fluidized_bed * gen_adj,
		pulverized_coal_variable_adj = pulverized_coal * gen_adj,
		stoker_variable_adj = stoker * gen_adj,
		other_comb_variable_adj = other_comb * gen_adj,
		subcritical_variable_adj = subcritical * gen_adj,
		supercritical_variable_adj = supercritical * gen_adj,
		ultrasupercritical_variable_adj = ultrasupercritical * gen_adj,
		coal_pollution_variable_adj = coal * real_pollution_control_costs_per_kW * gen_adj,
		coal_age_variable_adj = coal * age_relative_to_average * gen_adj,
		gas_pollution_variable_adj = natural_gas * real_pollution_control_costs_per_kW * gen_adj,
		gas_age_variable_adj = natural_gas * age_relative_to_average * gen_adj,
		oil_pollution_variable_adj = petroleum * real_pollution_control_costs_per_kW * gen_adj,
		oil_age_variable_adj = petroleum * age_relative_to_average * gen_adj
"

# get a list of all variables we need to select
#		omit anything that is synthetic, ie is on the left hand side of a variable
#		assignment; these can't be in the raw data
# alex gave me a list of 'fka' variables in the data_classes table- rename 
#   variables appropriately
AllLeftHandVariables <-
	bind_rows(pull_variables(raw_text), pull_variables(raw_text2)) %>%
		distinct(left_hand_variables) %>%
		rename(variable = left_hand_variables) %>%
		arrange(variable)

variables_to_select <-
	bind_rows(pull_variables(raw_text),pull_variables(raw_text2)) %>%
	distinct(right_hand_variables) %>%
	arrange(right_hand_variables) %>%
	rename(variable = right_hand_variables) %>%
	anti_join(AllLeftHandVariables) %>%  # drops 5 variables
	mutate(new_name = case_when(
		variable == 'CHP' ~ 'associated_combined_heat_power',
		variable == 'bypass_hrsg' ~ 'bypass_heat_recovery',
		variable == 'gasification' ~ 'solid_fuel_gasification',
		variable == 'ccs' ~ 'carbon_capture',
		variable == 'fluidized_bed' ~ 'fluidized_bed_tech',
		variable == 'pulverized_coal' ~ 'pulverized_coal_tech',
		variable == 'stoker' ~ 'stoker_tech',
		variable == 'other_comb' ~ 'other_combustion_tech',
		variable == 'subcritical' ~ 'subcritical_tech',
		variable == 'supercritical' ~ 'supercritical_tech',
		variable == 'ultrasupercritical' ~ 'ultrasupercritical_tech',
		variable == 'pollution_control_costs_per_kW' ~ 'pollution_control_costs_per_kw',
		variable == 'real_pollution_control_costs_per_kW' ~ 'real_pollution_control_costs_per_kw',
		variable == 'starts' ~ 'generator_starts',
		str_to_lower(variable) == 'ferc_cf' ~ 'gross_cf',
	)) %>%
		mutate(variables_to_select = coalesce(new_name, variable)) %>%
		pull(variables_to_select)


#### Perform actual pre-processing ####

true_remainder <- setdiff(variables_to_select, colnames(RawData))
true_intersect <- intersect(variables_to_select, colnames(RawData))

# SuiteOfMedianCf <- 
# 	# lightly modified version of the original, replacing dummy codes
# 	# with ordinal factor.
# 	RawData %>%
# 		group_by(plant_id_eia, prime_mover) %>%
# 		mutate(median_CF = median(ifelse(gross_cf <= 1.1, gross_cf, NA), na.rm=TRUE),
# 					 median_OpEx = median(ifelse(gross_cf <= 1.05, real_opex, NA), 
# 					 										 na.rm=TRUE),
# 					 ordinal_factor_median_CF = case_when(
# 					 	median_CF > 0.6 ~ 'high',
# 					 	median_CF > 0.4 ~ 'mid-high',
# 					 	median_CF > 0.2 ~ 'mid-low',
# 					 	median_CF >= 0.0 ~ 'low'
# 					 )
# 		) %>%
# 		ungroup %>%
# 		mutate(ordinal_factor_median_CF = ordered(ordinal_factor_median_CF,
# 			levels = c('low', 'mid-low', 'mid-high', 'high')))

SuiteOfMedianCf <-
	# Note that 0.2:0.4 essentially works as a mid-low bin on purpose
	RawData %>%
	group_by(plant_id_eia, prime_mover) %>%
		mutate(median_CF = median(ifelse(gross_cf <= 1.1, gross_cf, NA), na.rm=TRUE),
					 median_OpEx = median(ifelse(gross_cf <= 1.05, real_opex, NA), na.rm=TRUE),
					 high_median_CF = ifelse(median_CF>0.6,1,0),
					 mid_median_CF = ifelse(median_CF>0.4 & median_CF<=0.6,1,0),
					 low_median_CF = ifelse(median_CF<=0.2,1,0)
		) %>%
	ungroup

AgeObsAdj <-
	# note that the years are ordered in reverse
	RawData %>%
		distinct(state, report_year, wage_scale) %>%
		arrange(state, report_year) %>%
		mutate(report_year_fac = factor(report_year, ordered = T),
					 report_year_fac = fct_rev(report_year_fac)) %>%
		arrange(state, report_year_fac) %>%
		group_by(state) %>%
		mutate(age_obs_adj = cumsum(wage_scale)) %>%
		ungroup %>%
		select(state, report_year, age_obs_adj)

CumStarts <-
	RawData %>%
		arrange(report_year) %>%
		group_by(prime_mover, plant_id_eia) %>%
		summarize(cum_starts = cumsum(generator_starts)) %>%
		ungroup

# deselect the dummy codes
# mask <- variables_to_select %in% 
# 	c('high_median_CF', 'mid_median_CF', 'low_median_CF')
# variables_to_select <- variables_to_select[!mask	]

Data <-
	RawData %>%
		left_join(CumStarts) %>%
		left_join(AgeObsAdj) %>%
		left_join(SuiteOfMedianCf) %>%
		mutate(
			opex_over_capex = opex_per_kw / capex_per_kw,
			outlier_flag = ifelse(
				opex_over_capex >=0.5 | opex_over_capex <=0.002 | gross_cf>1.1, 1, 0)
			) %>%
		select(all_of(variables_to_select), 
					 outlier_flag, prime_mover, plant_id_eia, real_opex, 
					 real_opex_percentile, st, cc, gt, ic
		)

saveRDS(Data, file = 'clean_data/Data.RDS')