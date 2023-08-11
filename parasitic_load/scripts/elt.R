# ELT
# Parasitic Load project
# Andrew Bartnof
# abartnof.contractor@rmi.org
# 2023, for RMI


library(tidyverse)
# library(skimr)
library(arrow)
set.seed(1)

#### Load data ####
DataBySubplant <- read_parquet('input_data/data_by_subplant.parquet') %>%
	rowid_to_column %>%
	filter(prime_mover %in% c('CC', 'GT', 'ST'))

DataBySubplant$parasitic_load_pct
DataBySubplant$gross_generation_mwh

#### Transformations ####
# We'll evaluate our models using 5-fold cross validation.
# Assign each row a random marker, from 1:5
# Fold 1 will be trained on rows marked 2:5, and test on rows marked with 1,
# and so forth for all the other folds.

# Deselect rows that don't contain useful information for us.
# Create the dependent variable, parasitic_load.

num_folds <- 5L
fold_target <- sample.int(n = 5L, size = nrow(DataBySubplant), replace = TRUE)

columns_to_use <- c(
'rowid',
# "__index_level_0__"
# "age_in_current_year",
# "age_in_report_year",
"age_of_observation",
# "age_of_observation_secular_adj",
# "age_relative_to_prime_avg",
"arc",
"associated_combined_heat_power",
"biofuel_fraction",
"biofuel_gross_cf",
"biofuel_gross_mwh",
"biofuel_mmbtu",
"biofuel_net_mwh",
"bypass_heat_recovery",
"camd_capacity_mw",
"capacity_mw",
"capex",
"capex_per_kw",
"carbon_capture",
"coal_fraction",
"coal_gross_cf",
"coal_gross_mwh",
"coal_mmbtu",
"coal_net_mwh",
"cum_starts",
"duct_burners",
"fluidized_bed_tech",
"fuel_category",
"fuel_starts",
"generator_starts",
"gross_cf",
"gross_generation_mwh",
"gross_hr",
"heat_in_mmbtu",
# "inflator_to_2021",
"minor_fuels_fraction",
"natural_gas_fraction",
"natural_gas_gross_cf",
"natural_gas_gross_mwh",
"natural_gas_mmbtu",
"natural_gas_net_mwh",
"net_cf",
"net_generation_mwh",
"opex",
"opex_per_kw",
"other_combustion_tech",
"other_fraction",
"other_gas_fraction",
"other_gas_gross_cf",
"other_gas_gross_mwh",
"other_gas_mmbtu",
"other_gas_net_mwh",
"other_gross_cf",
"other_gross_mwh",
"other_mmbtu",
"other_net_mwh",
"parasitic_load_pct",
"petroleum_coke_fraction",
"petroleum_coke_gross_cf",
"petroleum_coke_gross_mwh",
"petroleum_coke_mmbtu",
"petroleum_coke_net_mwh",
"petroleum_fraction",
"petroleum_gross_cf",
"petroleum_gross_mwh",
"petroleum_mmbtu",
"petroleum_net_mwh",
# "pf_subplant_id",
# "plant_id_eia",
"pollution_control_costs_per_kw",
"prime_mover",
"pulverized_coal_tech",
"real_capex",
"real_opex",
"real_pollution_control_costs_per_kw",
# "report_date",
# "report_year",
"solid_fuel_gasification",
"step",
"stoker_tech",
"subcritical_tech",
# "subplant_id",
"supercritical_tech",
"ultrasupercritical_tech",
"wage_scale"
)

DataBySubplantClean <-
	DataBySubplant %>%
		select(all_of(columns_to_use)) %>%
		mutate(
			parasitic_load =
				(gross_generation_mwh - net_generation_mwh)
				/ (capacity_mw * 8760),
		) %>%
		bind_cols(fold_target = fold_target) %>%
		relocate(c(rowid, fold_target, prime_mover, gross_generation_mwh))

# Since we'll always be evaluating the models based on the same 5 folds,
# create an R object that's nested and ready to go for these tests.
NestedDataBySubplant <-
	DataBySubplantClean %>%
		expand_grid(fold_num = seq.int(from = 1L, to = num_folds)) %>%
		mutate(dataset = if_else(
			fold_num == fold_target,
			'test',
			'train'
		)) %>%
		select(-rowid, -fold_target) %>%
		group_by(fold_num, dataset) %>%
		nest %>%
		spread(dataset, data) %>%
		select(fold_num, train, test)

#### Save ####
write_csv(DataBySubplantClean, 'clean_data/clean_data_by_subplant.csv')
saveRDS(NestedDataBySubplant, 'clean_data/nested_data_by_subplant.RDS')
