library(conflicted)
library(skimr)
library(tidyverse)
library(janitor)
library(broom)
library(lubridate)
# library(Metrics)
conflict_prefer('select', 'dplyr')
conflict_prefer('filter', 'dplyr')
conflict_prefer('map2', 'purrr')
conflict_prefer('map', 'purrr')
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')
set.seed(1)

# Read data
CCopexmodel <- readRDS('clean_data/cc_opex_mod.RDS')
STopexmodel <- readRDS('clean_data/st_opex_mod.RDS')
GTopexmodel <- readRDS('clean_data/gt_opex_mod.RDS')
# Read in the fuel group and emissions map we have generated from EPA data and EIA documentation
fuel_group_and_emissions_map <- arrow::read_parquet("input_data/fuel_group_and_emissions_map.parquet")

# Script
class(STopexmodel)
STopex_variables <- tidy(STopexmodel)
STopex_variables <- STopex_variables %>%
  mutate(Prime = "ST")
CCopex_variables <- tidy(CCopexmodel)
CCopex_variables <- CCopex_variables %>%
  mutate(Prime = "CC")
GTopex_variables <- tidy(GTopexmodel)
GTopex_variables <- GTopex_variables %>%
  mutate(Prime = "GT")

reg_variables_opex <-
	bind_rows(STopex_variables, CCopex_variables, GTopex_variables) %>%
	select(Prime, term, estimate)

reg_variables_opex <- reg_variables_opex %>%
  pivot_wider(names_from = term, values_from = estimate) 
# NB: unnecessary because capex isn't done
# merge reg_variables and turn all NAs into 0s for predictions.
# reg_variables <- merge(reg_variables_capex,reg_variables_opex, by="Prime")
# cols<-colnames(reg_variables)
# reg_variables[cols]<-lapply(reg_variables[cols], function(x) ifelse(is.na(x),0,x))

# NB: could be replaced with just writing re_variables_opex
# write_parquet(reg_variables,"FERC_cost_regressions_coefficients.parquet")  

# Now, we use the opex and capex coefficiencts to estimate generator-level (actually, unit-level in the case of CCs) 
# opex and capex for all EIA-860 reporting fossil assets, making use of EIA-860, EIA-923, and CEMS data to 
# characterize the generators.

# Fuel map
fuel_map <- fuel_group_and_emissions_map %>% select(c(energy_source_code,fuel_group_code))

# Now, pull in current unit level data from EIA-860M and process for use to create both historical generation / fuel use and
# a counterfactual data set for use in the Patio model

all_years <- c(2008:2020)
all_months <- c(1:12)

unit_level_data <- arrow::read_parquet('input_data/unit_level_costs_with_flag.parquet.gzip')  # NB replace with final data when possible

unit_level_data <- unit_level_data %>% 
  rename(
    "plant_id_eia" = "Plant_ID",
    "prime_mover_code" = "Prime_with_CCs",
    "generator_id" = "Generator_ID"
  )

# Create plant level grouping file for aggregation
plant_grouping <- unit_level_data %>%
  select(c(
    plant_id_eia,
    State,
    Balancing_Authority_Code,
    Latitude,
    Longitude
  )) %>% 
	distinct()

# Next, we create unit level data for all years and months for each operating and retired asset

unit_level_data <- unit_level_data %>% 
  left_join(all_years, by = character(), copy = TRUE) %>% rename(report_year = y) %>%
  left_join(all_months, by = character(), copy = TRUE) %>% rename(report_month = y) %>%
  mutate(month_hours = unname(24*days_in_month(ymd(report_year*10000+report_month*100+1))))

# Filter unit level data for all years and months to create a list of plant and generator ids of 
# assets operating in each month and year for historical analysis
units_present_hist <- unit_level_data %>%
  filter(
    ((Operating_Year < report_year) | ((Operating_Year==report_year) & (Operating_Month <= report_month))) &
      (is.na(Retirement_Year) | 
         (Retirement_Year > report_year) | 
         ((Retirement_Year==report_year ) & (Retirement_Month > report_month))) & 
      (is.na(Planned_Retirement_Year) | 
         (Planned_Retirement_Year > report_year) | 
         ((Planned_Retirement_Year==report_year ) & (Planned_Retirement_Month > report_month)))) %>%
  select(c(
    plant_id_eia,
    generator_id,
    report_year,
    report_month,
    month_hours
  ))


# Create unit level data set for counterfactual analysis, which includes assets operating today for all years
# regardless of start of operations as well as all retired assets until their retirement date.
unit_level_data_cf <- unit_level_data %>%
  filter(
    (is.na(Retirement_Year) | 
       (Retirement_Year > report_year) | 
       ((Retirement_Year==report_year ) & (Retirement_Month > report_month))) & 
      (is.na(Planned_Retirement_Year) | 
         (Planned_Retirement_Year > report_year) | 
         ((Planned_Retirement_Year==report_year ) & (Planned_Retirement_Month > report_month))))

# Extract just key generator state / BAC identifier fields of all units present in the counterfactual case
units_present_cf <- unit_level_data_cf %>%
  select(c(
    plant_id_eia,
    generator_id,
    prime_mover_code,
    operational_capacity_in_report_year,
    State,
    Balancing_Authority_Code,
    report_year,
    report_month,
    month_hours
  )) %>% rename("prime_mover_code_hist" = "prime_mover_code","capacity_hist"="operational_capacity_in_report_year")

# NB paused until creation of historic_860_923_data
# Extract just the ntile data by generator to be used to map in estimated CFs
current_ntiles <- historic_860_923_data %>%
  filter(!is.na(fuel_group_code) & report_year==2020) %>%
  select(c(
    plant_id_eia,
    generator_id,
    report_month,
    fuel_group_code,
    cap_tile,
    lat_tile,
    long_tile,
  )) %>% distinct()

# Extract table with just historical average CF / starts data by state, BAC, ntiles to fill in counterfactual years

CF_starts_table <- historic_860_923_data %>%
  filter(!is.na(fuel_group_code)) %>%
  select(c(
    report_year,
    report_month,
    prime_mover_code_hist,
    fuel_group_code,
    State,
    Balancing_Authority_Code,
    cap_tile,
    lat_tile,
    long_tile,
    CF_net_ave,
    CF_gross_ave,
    gen_starts_ave,
    fuel_starts_ave
  )) %>% distinct()



