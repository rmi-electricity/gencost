# ELT
# Parasitic Load project
# Andrew Bartnof
# abartnof.contractor@rmi.org
# 2023, for RMI

library(tidyverse)
library(arrow)


# tech description variables have been pivoted to show capacity per fuel type
#### Load data ####

variables_to_select <- c(
# DV:
'gross_generation_mwh',
# IVs:
'capacity_mw',
'net_generation_mwh',
# 'heat_in_mmbtu',
'prime_mover',
#'balancing_authority_code_eia',
'state',
#'utility_id_eia',
'associated_combined_heat_power',
'duct_burners',
'bypass_heat_recovery',
'solid_fuel_gasification',
'carbon_capture',
'fluidized_bed_tech',
'pulverized_coal_tech',
'stoker_tech',
'other_combustion_tech',
'subcritical_tech',
'supercritical_tech',
'ultrasupercritical_tech',
'age_in_report_year',
'age_in_current_year',
'age_of_observation',
'age_relative_to_prime_avg',
'pollution_control_costs_per_kw',
#'respondent_id',
#'respondent_id_purchaser',
#'final_respondent_id',
#'final_ba_code',
'biofuel_mmbtu',
'coal_mmbtu',
'natural_gas_mmbtu',
'other_mmbtu',
'other_gas_mmbtu',
'petroleum_mmbtu',
'petroleum_coke_mmbtu',
'biofuel_net_mwh',
'coal_net_mwh',
'natural_gas_net_mwh',
'other_net_mwh',
'other_gas_net_mwh',
'petroleum_net_mwh',
'petroleum_coke_net_mwh',
# New columns, which add up to capacity_mw per row
'All Other',
'Coal Integrated Gasification Combined Cycle',
'Conventional Steam Coal',
'Landfill Gas',
'Municipal Solid Waste',
'Natural Gas Fired Combined Cycle',
'Natural Gas Fired Combustion Turbine',
'Natural Gas Steam Turbine',
'Other Gases',
'Other Waste Biomass',
'Petroleum Coke',
'Petroleum Liquids',
'Solar Thermal without Energy Storage',
'Wood/Wood Waste Biomass'
)

technology_columns <- c(
'All Other',
'Coal Integrated Gasification Combined Cycle',
'Conventional Steam Coal',
'Landfill Gas',
'Municipal Solid Waste',
'Natural Gas Fired Combined Cycle',
'Natural Gas Fired Combustion Turbine',
'Natural Gas Steam Turbine',
'Other Gases',
'Other Waste Biomass',
'Petroleum Coke',
'Petroleum Liquids',
'Solar Thermal without Energy Storage',
'Wood/Wood Waste Biomass'
)

DataBySubplant <- read_parquet('input_data/subplant_w_tech_by_capacity.parquet') %>%
	rowid_to_column %>%
	filter(prime_mover %in% c('CC', 'GT', 'ST')) %>%
	select(rowid, all_of(variables_to_select)) %>%
	mutate_at(technology_columns, replace_na, 0.0) # for the new tech columns, missing values mean 0.0 (they're the result of a pivot)

# There are ten or so columns that list fuels used.
# A missing value can be connoted to mean zero of that fuel was used,
# because it was inapplicable to the plant-- however, we want to note that for
# some of them, they COULD have used said fuel, but they didn't-- these plants
# would have an explicit 0.0.
# To remedy this, note which columns ending with _mmbtu have an explicit zero,
# and then fill all other missing values with zeros.

fuel_columns_which_need_explicit_zeros <-
	colMeans(is.na(DataBySubplant)) %>%
		enframe(name = 'variable', value = 'prop_missing') %>%
		filter(prop_missing > 0, str_detect(variable, 'mmbtu$')) %>%
		pull(variable)

fuel_columns_to_fill <-
	colMeans(is.na(DataBySubplant)) %>%
		enframe(name = 'variable', value = 'prop_missing') %>%
		filter(prop_missing > 0) %>%
		pull(variable)

JoinmeExplicitZeros <-
	DataBySubplant %>%
		select(rowid, all_of(fuel_columns_which_need_explicit_zeros)) %>%
		mutate_at(fuel_columns_which_need_explicit_zeros, ~near(., 0.0)) %>%
		mutate_at(fuel_columns_which_need_explicit_zeros, replace_na, FALSE) %>%
		rename_at(fuel_columns_which_need_explicit_zeros, ~str_c('is_explicit_zero_', .))

DataBySubplant <-
	DataBySubplant %>%
		mutate_at(fuel_columns_to_fill, replace_na, 0.0) %>%
		left_join(JoinmeExplicitZeros, by = 'rowid')

write_csv(DataBySubplant, 'clean_data/data_by_subplant.csv')
