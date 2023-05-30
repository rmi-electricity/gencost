# Power plant clustering and regressions project:
# Initial descriptive statistics 
# 2023 Andrew Bartnof for RMI

percentile <- function(xx){rank(xx)/length(xx)}

library(tidyverse)
library(skimr)
library(arrow)
library(conflicted)
conflicted::conflict_prefer('filter', 'dplyr')
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')
RawData <- read_parquet('input_data/data_for_pf_subplants.parquet')

Data <-
	RawData %>%
	rowid_to_column %>%
	mutate(
		# Now we turn to the process of regressing the FERC data to estimate capex and opex coefficients.
		# Start with (mostly) nominal, unadjusted variables for total capital cost per kW regression. The reason for this
		# is accounting - the original costs are reported as the sum of nominal costs in various years. However, as maintenance
		# capex may reasonably be expected to be constant in annual, real, state-adjusted dollars, and as cumulative
		# maintenance capex could represent some or substantially all the annual change in original costs, we do use a cumulative
		# adjusted age of observation rather than the raw age of observation to extract a real maintence capex.
		gas_fixed = natural_gas_fraction * capacity_mw,
		oil_fixed = petroleum_fraction * capacity_mw,
		other_fixed = other_gas_fraction * capacity_mw,
		coal_fixed = coal_fraction * capacity_mw,
		pollution_fixed = pollution_control_costs_per_kw * capacity_mw,
		age_fixed = age_relative_to_prime_avg * capacity_mw,
		CHP_fixed = associated_combined_heat_power * capacity_mw,
		duct_burners_fixed = duct_burners * capacity_mw,
		bypass_heat_recovery = bypass_heat_recovery * capacity_mw,
		gasification_fixed = solid_fuel_gasification * capacity_mw,
		ccs_fixed = carbon_capture * capacity_mw,
		fluidized_bed_fixed = fluidized_bed_tech * capacity_mw,
		pulverized_coal_fixed = pulverized_coal_tech * capacity_mw,
		stoker_fixed = stoker_tech * capacity_mw,
		other_comb_fixed = other_combustion_tech * capacity_mw,
		subcritical_fixed = subcritical_tech * capacity_mw,
		supercritical_fixed = supercritical_tech * capacity_mw,
		ultrasupercritical_fixed = ultrasupercritical_tech * capacity_mw,
		coal_pollution_fixed = coal_fraction * pollution_control_costs_per_kw * capacity_mw,
		coal_age_fixed = coal_fraction * age_relative_to_prime_avg * capacity_mw,
		gas_pollution_fixed = natural_gas_fraction * pollution_control_costs_per_kw * capacity_mw,
		gas_age_fixed = natural_gas_fraction * age_relative_to_prime_avg * capacity_mw,
		oil_pollution_fixed = petroleum_fraction * pollution_control_costs_per_kw * capacity_mw,
		oil_age_fixed = petroleum_fraction * age_relative_to_prime_avg * capacity_mw,
		coal_CHP_fixed = associated_combined_heat_power * coal_fraction * capacity_mw,
		gas_CHP_fixed = associated_combined_heat_power * natural_gas_fraction * capacity_mw,
		oil_CHP_fixed = associated_combined_heat_power * petroleum_fraction * capacity_mw,
		other_CHP_fixed = associated_combined_heat_power * other_gas_fraction * capacity_mw,
		age_obs_fixed = capacity_mw * age_of_observation_secular_adj,
		cum_starts_age_obs_fixed = cum_starts * capacity_mw * age_of_observation_secular_adj,
		CHP_age_obs_fixed = associated_combined_heat_power * capacity_mw * age_of_observation_secular_adj,
		duct_burners_age_obs_fixed = duct_burners * capacity_mw * age_of_observation_secular_adj,
		bypass_hrsg_age_obs_fixed = bypass_heat_recovery * capacity_mw * age_of_observation_secular_adj,
		gasification_age_obs_fixed = solid_fuel_gasification * capacity_mw * age_of_observation_secular_adj,
		ccs_age_obs_fixed = carbon_capture * capacity_mw * age_of_observation_secular_adj,
		fluidized_bed_age_obs_fixed = fluidized_bed_tech * capacity_mw * age_of_observation_secular_adj,
		pulverized_coal_age_obs_fixed = pulverized_coal_tech * capacity_mw * age_of_observation_secular_adj,
		stoker_age_obs_fixed = stoker_tech * capacity_mw * age_of_observation_secular_adj,
		other_comb_age_obs_fixed = other_combustion_tech * capacity_mw * age_of_observation_secular_adj,
		subcritical_age_obs_fixed = subcritical_tech * capacity_mw * age_of_observation_secular_adj,
		supercritical_age_obs_fixed = supercritical_tech * capacity_mw * age_of_observation_secular_adj,
		ultrasupercritical_age_obs_fixed = ultrasupercritical_tech * capacity_mw * age_of_observation_secular_adj,
		coal_age_obs_fixed = coal_fraction * capacity_mw * age_of_observation_secular_adj,
		gas_age_obs_fixed = natural_gas_fraction * capacity_mw * age_of_observation_secular_adj,
		oil_age_obs_fixed = petroleum_fraction * capacity_mw * age_of_observation_secular_adj,
		other_age_obs_fixed = other_gas_fraction * capacity_mw * age_of_observation_secular_adj,
		
		# Now define state wage level adjusted, real cost variables for OpEx regression
		capacity_adj = wage_scale * capacity_mw,
		starts_adj = generator_starts * capacity_adj,
		gas_starts_adj = natural_gas_fraction * starts_adj,
		oil_starts_adj = petroleum_fraction * starts_adj,
		other_starts_adj = other_gas_fraction * starts_adj,
		coal_starts_adj = coal_fraction * starts_adj,
		gas_fixed_adj = natural_gas_fraction * capacity_adj,
		oil_fixed_adj = petroleum_fraction * capacity_adj,
		other_fixed_adj = other_gas_fraction * capacity_adj,
		coal_fixed_adj = coal_fraction * capacity_adj,
		# high_median_CF_fixed_adj = high_median_CF * capacity_adj,
		# mid_median_CF_fixed_adj = mid_median_CF * capacity_adj,
		# low_median_CF_fixed_adj = low_median_CF * capacity_adj,
		# median_CF_fixed_adj = median_CF * capacity_adj,
		pollution_fixed_adj = real_pollution_control_costs_per_kw * capacity_adj,
		age_fixed_adj = age_relative_to_prime_avg * capacity_adj,
		age_obs_fixed_adj = age_of_observation * capacity_adj,
		CHP_fixed_adj = associated_combined_heat_power * capacity_adj,
		duct_burners_fixed_adj = duct_burners * capacity_adj,
		bypass_hrsg_fixed_adj = bypass_heat_recovery * capacity_adj,
		gasification_fixed_adj = solid_fuel_gasification * capacity_adj,
		ccs_fixed_adj = carbon_capture * capacity_adj,
		fluidized_bed_fixed_adj = fluidized_bed_tech * capacity_adj,
		pulverized_coal_fixed_adj = pulverized_coal_tech * capacity_adj,
		stoker_fixed_adj = stoker_tech * capacity_adj,
		other_comb_fixed_adj = other_combustion_tech * capacity_adj,
		subcritical_fixed_adj = subcritical_tech * capacity_adj,
		supercritical_fixed_adj = supercritical_tech * capacity_adj,
		ultrasupercritical_fixed_adj = ultrasupercritical_tech * capacity_adj,
		coal_pollution_fixed_adj = coal_fraction * real_pollution_control_costs_per_kw * capacity_adj,
		coal_age_fixed_adj = coal_fraction * age_relative_to_prime_avg * capacity_adj,
		gas_pollution_fixed_adj = natural_gas_fraction * real_pollution_control_costs_per_kw * capacity_adj,
		gas_age_fixed_adj = natural_gas_fraction * age_relative_to_prime_avg * capacity_adj,
		oil_pollution_fixed_adj = petroleum_fraction * real_pollution_control_costs_per_kw * capacity_adj,
		oil_age_fixed_adj = petroleum_fraction * age_relative_to_prime_avg * capacity_adj,
		gen = gross_cf * capacity_mw * ifelse(report_year %% 4 ==0,8784,8760),
		gen_adj = wage_scale * gen,
		# high_median_CF_adj = high_median_CF * gen_adj,
		# mid_median_CF_adj = mid_median_CF * gen_adj,
		# low_median_CF_adj = low_median_CF * gen_adj,
		# median_CF_adj = median_CF * gen_adj,
		gas_variable_adj = natural_gas_fraction * gen_adj,
		oil_variable_adj = petroleum_fraction * gen_adj,
		other_variable_adj = other_gas_fraction * gen_adj,
		coal_variable_adj = coal_fraction * gen_adj,
		pollution_variable_adj = real_pollution_control_costs_per_kw * gen_adj,
		age_variable_adj = age_relative_to_prime_avg * gen_adj,
		age_obs_variable_adj = age_of_observation * gen_adj,
		CHP_variable_adj = associated_combined_heat_power * gen_adj,
		duct_burners_variable_adj = duct_burners * gen_adj,
		bypass_hrsg_variable_adj = bypass_heat_recovery * gen_adj,
		gasification_variable_adj = solid_fuel_gasification * gen_adj,
		ccs_variable_adj = carbon_capture * gen_adj,
		fluidized_bed_variable_adj = fluidized_bed_tech * gen_adj,
		pulverized_coal_variable_adj = pulverized_coal_tech * gen_adj,
		stoker_variable_adj = stoker_tech * gen_adj,
		other_comb_variable_adj = other_combustion_tech * gen_adj,
		subcritical_variable_adj = subcritical_tech * gen_adj,
		supercritical_variable_adj = supercritical_tech * gen_adj,
		ultrasupercritical_variable_adj = ultrasupercritical_tech * gen_adj,
		coal_pollution_variable_adj = coal_fraction * real_pollution_control_costs_per_kw * gen_adj,
		coal_age_variable_adj = coal_fraction * age_relative_to_prime_avg * gen_adj,
		gas_pollution_variable_adj = natural_gas_fraction * real_pollution_control_costs_per_kw * gen_adj,
		gas_age_variable_adj = natural_gas_fraction * age_relative_to_prime_avg * gen_adj,
		oil_pollution_variable_adj = petroleum_fraction * real_pollution_control_costs_per_kw * gen_adj,
		oil_age_variable_adj = petroleum_fraction * age_relative_to_prime_avg * gen_adj,
		real_opex_per_kw = real_opex / capacity_mw  # is this right?
	) %>%
		# redefine as real_opex per kw
		# notes: x * inflator_to_2021 = x_real
		# use here real_opex / capacity AS real_opex_per_kw and use this for the percentiles-- per prime mover
		group_by(prime_mover) %>%
		mutate(real_opex_percentile = percentile(real_opex)) %>%
		ungroup %>%
		mutate(
		real_opex_percentile = percentile(real_opex), # overall or per prime_mover type?
		opex_over_capex = opex_per_kw / capex_per_kw,
		is_outlier_general = ifelse(opex_over_capex >= 0.5 | opex_over_capex <= 0.002 | gross_cf > 1.1, 1, 0),
		# outlier_flag = ifelse(opex_over_capex >=0.5 | opex_over_capex <=0.002 | FERC_CF>1.1, 1, 0)) %>%
		is_safe_st = (prime_mover == 'ST') & (!is_outlier_general) &
			(gross_cf <= 1.1), 
		# ,data=FERC_Data,subset=(ST==1 & FERC_CF<=1.1 & outlier_flag==0))
		is_safe_cc = (prime_mover == 'CC') & (!is_outlier_general) & 
			(real_opex_percentile >= 0.03) & (real_opex_percentile <= 0.97) &
			(coal_fraction == 0),
		 # ,data=FERC_Data,subset=(CC==1 & coal==0 & outlier_flag==0 & real_opex_percentile<=0.97 & real_opex_percentile>=0.03))
		is_safe_gt = (prime_mover == 'GT') & (!is_outlier_general) & 
			(real_opex_percentile<=0.97) & (real_opex_percentile>=0.03),
		# ,data=FERC_Data,subset=(GT==1 & outlier_flag==0 & real_opex_percentile<=0.97 & real_opex_percentile>=0.03))
		
		# Collect all of the above filters into one column
		consolidated_regression_filter = case_when(
			prime_mover == 'CC' ~ is_safe_cc,
			prime_mover == 'GT' ~ is_safe_gt,
			prime_mover == 'ST' ~ is_safe_st,
			T ~ as.logical(NA_real_)
		)
	)

# Establish the formulas that we'll use for regressions
# added gross_cf to all formulas
	
# removed:
# CHP_variable_adj +
# pulverized_coal_fixed_adj +
# high_median_CF_adj +
# high_median_CF_fixed_adj +
# median_CF_adj +
# median_CF_fixed_adj +
# mid_median_CF_adj +
# mid_median_CF_fixed_adj +
formula_st_real_opex <- 'real_opex ~ 0 + 
age_obs_variable_adj +
age_variable_adj +
capacity_adj +
fluidized_bed_variable_adj +
gas_age_fixed_adj +
gas_age_variable_adj +
gas_fixed_adj +
gas_pollution_fixed_adj +
gas_starts_adj +
gen_adj +
gross_cf +
oil_fixed_adj +
pollution_fixed_adj +
pollution_variable_adj +
starts_adj +
supercritical_fixed_adj +
supercritical_variable_adj'

# removed:
# high_median_CF_adj +
# high_median_CF_fixed_adj +
# low_median_CF_adj +
# low_median_CF_fixed_adj +
# median_CF_adj +
# median_CF_fixed_adj +
# mid_median_CF_adj +
# mid_median_CF_fixed_adj +
formula_cc_real_opex <- 'real_opex ~ 0 +
CHP_fixed_adj +
age_obs_variable_adj +
age_variable_adj +
capacity_adj +
duct_burners_fixed_adj +
gen_adj +
gross_cf + 
oil_age_fixed_adj +
pollution_variable_adj +
starts_adj'

# removed:
# high_median_CF_adj +
# low_median_CF_adj +
# low_median_CF_fixed_adj +
# median_CF_adj +
# median_CF_fixed_adj +
# mid_median_CF_adj +
# mid_median_CF_fixed_adj +
formula_gt_real_opex <- 'real_opex ~ 0 +
age_fixed_adj +
age_obs_fixed_adj +
age_obs_variable_adj +
age_variable_adj +
capacity_adj +
gen_adj +
gross_cf +
oil_age_fixed_adj +
oil_fixed_adj +
oil_starts_adj +
oil_variable_adj +
starts_adj
'
FormulasRealOpex <- tribble(
	~prime_mover, ~formula,
	'cc', formula_cc_real_opex,
	'gt', formula_gt_real_opex,
	'st', formula_st_real_opex
)

variables_for_regressions <-
	FormulasRealOpex %>%
		mutate(variables = str_extract_all(formula, '[A-Za-z_]+')) %>%
		unnest(variables) %>%
		distinct(variables) %>%
		arrange(variables) %>%
		pull


#### Subset to only the necessary variables, and write the dataset to disk ####
RawData %>%
	select(contains('cf')) %>%
	colnames %>%
	sort

variables_for_sanity_check <- c('gross_cf', 'generator_starts', 'capacity_mw',
	'age_relative_to_prime_avg', 'capacity_mw', 'generator_starts', 'age_in_report_year',
	"biofuel_gross_cf", "coal_gross_cf", "gross_cf", "natural_gas_gross_cf",
	"net_cf", "other_gas_gross_cf", "other_gross_cf", "petroleum_coke_gross_cf",
	"petroleum_gross_cf")

variables_all <- 
	c('rowid', 'plant_id_eia', 'prime_mover', variables_for_regressions, 
		variables_for_sanity_check, 'consolidated_regression_filter')

variables_all %>%
	# Make sure all variables are present in the dataset!
	enframe(name = NULL, value = 'variable') %>%
	arrange(variable) %>%
	mutate(is_in_data = variable %in% colnames(Data)) %>%
	filter(!is_in_data)

Data %>%
	filter(prime_mover %in% c('ST', 'CC', 'GT')) %>%  # omit 2 IC plants
	select(all_of(variables_all)) %>%
	write_csv(file = 'clean_data/data.csv')

FormulasRealOpex %>%
	write_csv(file = 'clean_data/formulas_real_opex.csv')

saveRDS(variables_for_regressions, 'clean_data/variables_for_regressions.RDS')
saveRDS(variables_for_sanity_check, 'clean_data/variables_for_sanity_check.RDS')

variables_for_clusters <- variables_for_regressions[variables_for_regressions != 'real_opex']
saveRDS(variables_for_clusters, 'clean_data/variables_for_clusters.RDS')
