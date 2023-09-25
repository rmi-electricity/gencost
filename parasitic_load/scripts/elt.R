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
'rowid',
# DV:
'parasitic_load',  # note: gross_generation_mwh is now not in the model
# IVs:
'gross_generation_mwh', # TODO: remove from feature engineering
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

# remove out of a sense of caution:
# 'biofuel_mmbtu',
# 'coal_mmbtu',
# 'natural_gas_mmbtu',
# 'other_mmbtu',
# 'other_gas_mmbtu',
# 'petroleum_mmbtu',
# 'petroleum_coke_mmbtu',
'biofuel_net_mwh',
'coal_net_mwh',
'natural_gas_net_mwh',
'other_net_mwh',
'other_gas_net_mwh',
'petroleum_net_mwh',
'petroleum_coke_net_mwh'
# New columns, which add up to capacity_mw per row
# 'All Other',
# 'Coal Integrated Gasification Combined Cycle',
# 'Conventional Steam Coal',
# 'Landfill Gas',
# 'Municipal Solid Waste',
# 'Natural Gas Fired Combined Cycle',
# 'Natural Gas Fired Combustion Turbine',
# 'Natural Gas Steam Turbine',
# 'Other Gases',
# 'Other Waste Biomass',
# 'Petroleum Coke',
# 'Petroleum Liquids',
# 'Solar Thermal without Energy Storage',
# 'Wood/Wood Waste Biomass'
)

DataBySubplant <- read_parquet('input_data/subplant_w_tech_by_capacity.parquet') %>%
	rowid_to_column %>%
	mutate(
		parasitic_load = (gross_generation_mwh - net_generation_mwh) / (capacity_mw * 8760)
	) %>%
	filter(
		prime_mover %in% c('CC', 'GT', 'ST'),
		parasitic_load >= 0.0
	) %>%
	select(all_of(variables_to_select))

write_csv(DataBySubplant, 'clean_data/data_by_subplant.csv')
