library(tidyverse)
library(arrow)

# 1
historic_860_923_data <- read_parquet('input_data/data_for_pf_subplants.parquet')
# the historical data was monthly, not annual
# 	try to just say that each month is january
# 	if this doesn't work, ???

# historic_860_923_data <- read_parquet("complete_historic_unit_data.parquet")

# generator_id can be replaced with pf_subplant_id
# prime_mover_code_hist -> prime_mover
# get report_month from report_date
# uday's parasitic_load was in mwh, not pct
historic_860_923_data %>% 
	colnames %>%
	sort

# 2
parasitic_load_est <- 
	historic_860_923_data %>% 
	select(c(
		plant_id_eia, generator_id, prime_mover_code_hist, report_year, report_month, 
		parasitic_load, capacity_hist, fuel_group_code, net_generation_mwh_final, 
		gross_gen_final, fuel_frac, month_hours
	)) %>% 
	group_by(plant_id_eia, generator_id, report_year, fuel_group_code) %>% 
	summarize(
		num_par_load_lines = sum(!(is.na(parasitic_load) | net_generation_mwh_final == 0), na.rm = TRUE), 
		parasitic_load = sum(ifelse(net_generation_mwh_final ==  0, NA, parasitic_load * fuel_frac), na.rm = TRUE), 
		capacity_hist = sum(ifelse(is.na(parasitic_load) | net_generation_mwh_final == 0, NA, capacity_hist * fuel_frac/num_par_load_lines), na.rm = TRUE), 
		num_hours = sum(month_hours), prime_mover_code_hist = prime_mover_code_hist, 
		CF_para = (parasitic_load/(capacity_hist * num_hours))
	) %>% 
	ungroup %>% 
	distinct %>% 
	group_by(plant_id_eia, prime_mover_code_hist, report_year, fuel_group_code) %>% 
	summarize(
		capacity_hist = sum(ifelse(is.na(parasitic_load), NA, capacity_hist), na.rm = TRUE), 
		parasitic_load = sum(parasitic_load,  na.rm = TRUE)
	) %>% 
	ungroup() %>% 
	distinct()
