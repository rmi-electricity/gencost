library(tidyverse)
library(skimr)
library(randomForest)
library(arrow)
library(conflicted)
conflicted::conflict_prefer('map', 'purrr')
#library(naivebayes)


#### ELT ####
RawData <- arrow::read_parquet('input_data/data_for_pf_subplants.parquet') %>%
	as_tibble

find_mode <- function(x) {
	# https://stackoverflow.com/questions/2547402/how-to-find-the-statistical-mode
	ux <- unique(x)
	ux[which.max(tabulate(match(x, ux)))]
}

rmse <- function(y_fit, y_true){
	sqrt(
		mean(
			(y_fit - y_true)^2
		)
	)
}



# Prima facie, excluded columns (contains IDs, codes, etc)
#"__index_level_0__"       
#"balancing_authority_code_eia"       
#"block_group_id"                     
#"census_tract_id"                    
#"county_id"                          
#"fuel_group_energy_source_code_860m" 
#"fuel_group_rmi_energy_source_code_1"
#"fuel_group_rmi_energy_source_code_2"
#"fuel_group_rmi_energy_source_code_3"
#"fuel_group_rmi_energy_source_code_4"
#"fuel_group_rmi_energy_source_code_5"
#"fuel_group_rmi_energy_source_code_6"
#"geoid",
#"latitude"                           
#"longitude"                          
#"pf_subplant_id"                     
#"plant_id_eia"                       
#"plant_name_eia"                     
#"respondent_id"                      
#"rmi_energy_source_code_1"           
#"rmi_energy_source_code_2"           
#"rmi_energy_source_code_3"           
#"rmi_energy_source_code_4"           
#"rmi_energy_source_code_5"           
#"rmi_energy_source_code_6"           
#"state"                              
#"state_id"                           
#"utility_id_eia"                     
#"utility_name"                       
good_columns <- c(
"age",
"age_as_of_2021",
"associated_combined_heat_power",
"avg_plant_prime_fuel_age",
"bypass_heat_recovery",
"camd_capacity_mw",
"capacity_mw",
"carbon_capture",
"co2_tons",
"cofire_fuels",
"diff_age_and_avg_plant_prime_fuel",
"duct_burners",
"energy_source_code_860m",
"final_gen_type",
"fluidized_bed_tech",
"fuel_code_coal",
"fuel_code_natural_gas",
"fuel_code_other_gas",
"fuel_code_petroleum",
"fuel_code_petroleum_coke",
"fuel_consumed_for_electricity_mmbtu",
"fuel_starts",
"generator_starts",
"gross_cf",
"gross_generation_mwh",
"gross_hr",
"heat_in_mmbtu",
"multiple_fuels",
"net_cf",
"net_generation_mwh",
"net_hr",
"operating_date",
"operational_capacity_in_report_year",
"other_combustion_tech",
"parasitic_load_pct",
"patio_ba_code",
"planned_retirement_month",
"planned_retirement_year",
"pollution_control_costs_per_kw",
"prime_mover",
"pulverized_coal_tech",
"report_date",
"retirement_month",
"retirement_year",
"rmi_fuel_group_1",                  
"rmi_fuel_group_2",                   
"rmi_fuel_group_3",                   
"rmi_fuel_group_4",                   
"sector",
"solid_fuel_gasification",
"stoker_tech",
"subcritical_tech",
"supercritical_tech",
"technology_1",
"ultrasupercritical_tech"
)

Data <-
	RawData %>%
		select(good_columns) %>%
		select_if(is.numeric)

is.na(Data) <- sapply(Data, is.infinite)

columns_to_impute <-
	Data %>%
		select(-generator_starts) %>%
		colnames

Imputed <-
	# https://stackoverflow.com/questions/25835643/replace-missing-values-with-column-mean
	Data %>%
		mutate_at(columns_to_impute, as.numeric) %>%
		mutate_at(columns_to_impute, 
							~if_else(is.na(.x), mean(.x, na.rm = T), .x)
		)
		
	

# Data$generator_starts will stand as the DV here

#### univariate imputation ####
RMSEUnivariate <-
	Data %>%
		select(generator_starts) %>%
		rowid_to_column('i') %>%
		nest(data = everything()) %>%
		expand_grid(sample_num = seq(1, 100)) %>%
		mutate(
					 X = map(data, sample_frac, size = 0.7, replace = F),
					 y_true = map2(data, X, anti_join, by = c('i', 'generator_starts')),
					 X = map(X, pull, 'generator_starts'),
					 mean = map_dbl(X, mean),
					 median = map_dbl(X, median),
					 mode = map_dbl(X, find_mode)
		) %>%
		select(-data, -X) %>%
		unnest(y_true) %>%
		rename(y_true = generator_starts) %>%
		gather(model, y_fit, -sample_num, -i, -y_true) %>%
		mutate(error = y_fit - y_true,
					 error_sq = error^2
		) %>%
		group_by(sample_num, model) %>%
		summarize(mean_error_sq = mean(error_sq),
							rmse = sqrt(mean_error_sq)
		) %>%
		ungroup
	
#### RMSE lm ####

RMSElm <-
	Imputed %>%
		rowid_to_column('i') %>%
		nest(data = everything()) %>%
		expand_grid(sample_num = seq(1, 100)) %>%
		mutate(
			Train = map(data, sample_frac, size = 0.7, replace = F),
			Test = map2(data, Train, anti_join, by = 'i'),
			mod_lm = map(Train, ~lm(data = .x, formula = generator_starts ~.)),
			y_fit = map2(mod_lm, Test, ~predict(object = .x, newdata = .y)),
			y_true = map(Test, 'generator_starts')
		) %>%
		select(sample_num, y_fit, y_true) %>%
		unnest(cols = c(y_fit, y_true)) %>%
		group_by(sample_num) %>%
		summarize(rmse = rmse(y_fit, y_true)) %>%
		ungroup

RMSElm %>%
	mutate(model = 'linear model') %>%
	bind_rows(RMSEUnivariate) %>%
	select(model, sample_num, rmse) %>%
	ggplot(aes(x = model, y = rmse, group = model)) +
	geom_boxplot() +
	expand_limits(y = 0) +
	labs(x = 'Model', y = 'RMSE')

Data$generator_starts %>%
	skim

Data %>%
	ggplot(aes(x = generator_starts)) +
	geom_histogram()
