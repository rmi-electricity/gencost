# Final work with coefficients
# 1. get all the regression variables ready; get PCA scores; weight PCA scores;
# put into cluster
# 2. Run final metric transformations

library(tidyverse)
library(skimr)
library(conflicted)
# library(broom)
library(arrow)
library(lubridate)
library(flexclust)
library(lavaan)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')
HistoricRaw <- read_parquet('input_data/historic_data_gen_level.parquet') %>%
	rowid_to_column

NestedCoefficients <- readRDS('clean_data/nested_coefficients.RDS')
ClusteredHist <- readRDS('clean_data/clustered_hist.RDS')

variables_for_sanity_check_cc <- readRDS('clean_data/variables_for_sanity_check_cc.RDS')
variables_for_sanity_check_gt <- readRDS('clean_data/variables_for_sanity_check_gt.RDS')
variables_for_sanity_check_st <- readRDS('clean_data/variables_for_sanity_check_st.RDS')

# Join each input row to its cluster
# Join each cluster to its coefficients
# Run through the final data transformations
Coefficients <-
	NestedCoefficients %>%
		unnest(coefficients) %>%
		select(prime_mover, num_clusters, cluster, measure, estimate) %>%
		spread(measure, estimate) %>%
		mutate_if(is.numeric, replace_na, 0.0)

PreparedHist <-
	ClusteredHist %>%
		unnest(c(rowid, cluster)) %>%
		inner_join(HistoricRaw, by = c('prime_mover', 'rowid')) %>%
		select(-gross_cf) %>%
		left_join(Coefficients, by = c("prime_mover", "num_clusters", "cluster"))

# Output <-
perform_final_transformations <- function(X){
	X %>%
		# Prelim variables
		mutate(
			capacity_adj = wage_scale * capacity_mw,
			pulverized_coal_fixed_adj = pulverized_coal_tech * capacity_adj,
			CHP_variable_adj = associated_combined_heat_power * gen_adj,
			duct_burners_variable_adj = duct_burners * gen_adj,
			oil_age_variable_adj = petroleum_fraction * age_relative_to_prime_avg * gen_adj,
		) %>%
	mutate(
		real_fixed_opex_per_kW_no_starts_est = ( 
			(capacity_adj * wage_scale) + 
			# (median_CF_fixed_adj * median_CF * wage_scale ) +
			# (high_median_CF_fixed_adj * high_median_CF * wage_scale ) +
			# (mid_median_CF_fixed_adj * mid_median_CF * wage_scale ) +
			# (low_median_CF_fixed_adj * low_median_CF * wage_scale ) +
			(gas_fixed_adj * natural_gas_fraction * wage_scale) + 
			# (gas_fixed_adj * fuel_frac_natural_gas * wage_scale) + 
			(oil_fixed_adj * petroleum_fraction * wage_scale) +
			# (oil_fixed_adj * fuel_frac_petroleum * wage_scale) +
			(CHP_fixed_adj * associated_combined_heat_power * wage_scale) +
			# (CHP_fixed_adj * chp * wage_scale) +
			(pollution_fixed_adj * pollution_control_costs_per_kw * wage_scale) +
			# (pollution_fixed_adj * pollution_control_costs_per_kW * wage_scale) +
			(pulverized_coal_fixed_adj * pulverized_coal_tech * wage_scale) +
			# (pulverized_coal_fixed_adj * pulverized_coal * wage_scale) +
			(duct_burners_fixed_adj * duct_burners * wage_scale) +
			(supercritical_fixed_adj * supercritical_tech * wage_scale) +
			# (supercritical_fixed_adj * supercritical * wage_scale) +
			(age_fixed_adj * age_relative_to_prime_avg * wage_scale) +
			# (age_fixed_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
			(oil_age_fixed_adj * age_relative_to_prime_avg * petroleum_fraction * wage_scale) +
			# (oil_age_fixed_adj * diff_age_and_avg_plant_prime_fuel * fuel_frac_petroleum * wage_scale) +
			(gas_age_fixed_adj * age_relative_to_prime_avg * natural_gas_fraction * wage_scale) +
			# (gas_age_fixed_adj * diff_age_and_avg_plant_prime_fuel * fuel_frac_natural_gas * wage_scale) +
			(gas_pollution_fixed_adj * natural_gas_fraction * pollution_control_costs_per_kw * wage_scale)),
			# (gas_pollution_fixed_adj * fuel_frac_natural_gas * pollution_control_costs_per_kW * wage_scale)),
		real_opex_per_kW_start = starts_adj +  (gas_starts_adj * natural_gas_fraction) + 
		# real_opex_per_kW_start = starts_adj +  (gas_starts_adj * fuel_frac_natural_gas) + 
			(oil_starts_adj * petroleum_fraction),
			# (oil_starts_adj * fuel_frac_petroleum),
		real_fixed_opex_per_kW_age_coeff = age_obs_fixed_adj * wage_scale
	) %>%
	# Calculate estimated real variable costs opex, again breaking out coefficients dependent on age of observation
	# only for historical cost estimation
	mutate(real_variable_opex_per_MWh_est = (
			(gen_adj * wage_scale) +
				# (median_CF_adj * median_CF * wage_scale ) +
				# (high_median_CF_adj * high_median_CF * wage_scale ) +
				# (mid_median_CF_adj * mid_median_CF * wage_scale ) +
				# (low_median_CF_adj * low_median_CF * wage_scale ) +
				(oil_variable_adj * petroleum_fraction * wage_scale) +
				# (oil_variable_adj * fuel_frac_petroleum * wage_scale) +
				(pollution_variable_adj * pollution_control_costs_per_kw * wage_scale) +
				# (pollution_variable_adj * pollution_control_costs_per_kW * wage_scale) +
				(age_variable_adj * age_relative_to_prime_avg * wage_scale) +
				# (age_variable_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
				(fluidized_bed_variable_adj * fluidized_bed_tech * wage_scale) +
				# (fluidized_bed_variable_adj * fluidized_bed * wage_scale) +
				(CHP_variable_adj * associated_combined_heat_power * wage_scale) +
				# (CHP_variable_adj * chp * wage_scale) +
				(supercritical_variable_adj * supercritical_tech * wage_scale) +
				# (supercritical_variable_adj * supercritical * wage_scale) +
				(gas_age_variable_adj * natural_gas_fraction * age_relative_to_prime_avg * wage_scale) +
				# (gas_age_variable_adj * fuel_frac_natural_gas * diff_age_and_avg_plant_prime_fuel * wage_scale) +
				(duct_burners_variable_adj * duct_burners * wage_scale) +
				(oil_age_variable_adj * petroleum_fraction * age_relative_to_prime_avg * wage_scale)),
				# (oil_age_variable_adj * fuel_frac_petroleum * diff_age_and_avg_plant_prime_fuel * wage_scale)),
			real_variable_opex_per_MWh_age_coeff = (age_obs_variable_adj * wage_scale)
		)
}
Output <- perform_final_transformations(PreparedHist)
Output

#### Sanity check on output variables ####
# 1. in which clusters do we see low output variables?
PlotmeBoxes <-
	Output %>%
		select(-rowid) %>%
		mutate_at(c('prime_mover', 'num_clusters', 'cluster'), factor)

PlotmeBoxes %>%
	ggplot(aes(x = cluster, y = real_fixed_opex_per_kW_no_starts_est)) +
	geom_boxplot() +
	facet_grid(prime_mover ~ num_clusters, scales = 'free_x') +
	scale_y_continuous(labels = scales::dollar_format()) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = 'Cluster', y = '', title = 'real_fixed_opex_per_kW_no_starts_est')

PlotmeBoxes %>%
	ggplot(aes(x = cluster, y = real_variable_opex_per_MWh_est)) +
	geom_boxplot() +
	facet_grid(prime_mover ~ num_clusters, scales = 'free_x') +
	scale_y_continuous(labels = scales::dollar_format()) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = 'Cluster', y = '', title = 'real_variable_opex_per_MWh_est')

PlotmeBoxes %>%
	ggplot(aes(x = cluster, y = real_opex_per_kW_start)) +
	geom_boxplot() +
	facet_grid(prime_mover ~ num_clusters, scales = 'free_x') +
	scale_y_continuous(labels = scales::dollar_format()) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = 'Cluster', y = '', title = 'real_opex_per_kW_start')

PlotmeBoxes %>%
	# Histograms
	count(prime_mover, num_clusters, cluster) %>%
	ggplot(aes(x = cluster, y = n)) +
	geom_col() +
	facet_grid(prime_mover ~ num_clusters, scales = 'free_x') +
	scale_y_continuous(labels = scales::comma_format()) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = 'Cluster', y = 'Count', title = 'Size of clusters')

# SEM
# 2. SEM showing what leads to low output variables
variables_for_sanity_check_all <-
	intersect(
		intersect(variables_for_sanity_check_cc, variables_for_sanity_check_gt),
		variables_for_sanity_check_st)
variables_for_sanity_check_all

Modelme <-
	Output %>%
		filter(num_clusters == 1) %>%
		mutate_if(is.numeric, ~as.vector(scale(.)))

my_formula <- '
# Regressions
real_fixed_opex_per_kW_no_starts_est ~
	+ age_in_report_year
	+ capacity_mw
	+ generator_starts
	+ gross_cf
	+ natural_gas_fraction
	+ petroleum_fraction
	# + minor_fuels_fraction

real_variable_opex_per_MWh_est ~
	+ age_in_report_year
	+ capacity_mw
	+ generator_starts
	+ gross_cf
	+ natural_gas_fraction
	+ petroleum_fraction
	# + minor_fuels_fraction

real_opex_per_kW_start ~
	+ age_in_report_year
	+ capacity_mw
	+ generator_starts
	+ gross_cf
	+ natural_gas_fraction
	+ petroleum_fraction
	# + minor_fuels_fraction

# Correlations
real_fixed_opex_per_kW_no_starts_est ~~ real_variable_opex_per_MWh_est
real_fixed_opex_per_kW_no_starts_est ~~ real_opex_per_kW_start
real_variable_opex_per_MWh_est ~~ real_opex_per_kW_start
'

sem_fit <- sem(my_formula, data = Modelme)
summary(sem_fit)

#
HistoricRaw %>%
		mutate(
			capacity_adj = wage_scale * capacity_mw,
			pulverized_coal_fixed_adj = pulverized_coal_tech * capacity_adj,
			gen = gross_cf * capacity_mw * ifelse(report_year %% 4 ==0,8784,8760),
			gen_adj = wage_scale * gen,
			CHP_variable_adj = associated_combined_heat_power * gen_adj,
			duct_burners_variable_adj = duct_burners * gen_adj,
			oil_age_variable_adj = petroleum_fraction * age_relative_to_prime_avg * gen_adj,
			gas_fixed_adj = natural_gas_fraction * capacity_adj,
			oil_fixed_adj = petroleum_fraction * capacity_adj,
		) %>%
	mutate(
		real_fixed_opex_per_kW_no_starts_est = ( 
			(capacity_adj * wage_scale) + 
			# (median_CF_fixed_adj * median_CF * wage_scale ) +
			# (high_median_CF_fixed_adj * high_median_CF * wage_scale ) +
			# (mid_median_CF_fixed_adj * mid_median_CF * wage_scale ) +
			# (low_median_CF_fixed_adj * low_median_CF * wage_scale ) +
			(gas_fixed_adj * natural_gas_fraction * wage_scale) + 
			# (gas_fixed_adj * fuel_frac_natural_gas * wage_scale) + 
			(oil_fixed_adj * petroleum_fraction * wage_scale) +
			# (oil_fixed_adj * fuel_frac_petroleum * wage_scale) +
			(CHP_fixed_adj * associated_combined_heat_power * wage_scale) +
			# (CHP_fixed_adj * chp * wage_scale) +
			(pollution_fixed_adj * pollution_control_costs_per_kw * wage_scale) +
			# (pollution_fixed_adj * pollution_control_costs_per_kW * wage_scale) +
			(pulverized_coal_fixed_adj * pulverized_coal_tech * wage_scale) +
			# (pulverized_coal_fixed_adj * pulverized_coal * wage_scale) +
			(duct_burners_fixed_adj * duct_burners * wage_scale) +
			(supercritical_fixed_adj * supercritical_tech * wage_scale) +
			# (supercritical_fixed_adj * supercritical * wage_scale) +
			(age_fixed_adj * age_relative_to_prime_avg * wage_scale) +
			# (age_fixed_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
			(oil_age_fixed_adj * age_relative_to_prime_avg * petroleum_fraction * wage_scale) +
			# (oil_age_fixed_adj * diff_age_and_avg_plant_prime_fuel * fuel_frac_petroleum * wage_scale) +
			(gas_pollution_fixed_adj * natural_gas_fraction * pollution_control_costs_per_kw * wage_scale)),
			# (gas_pollution_fixed_adj * fuel_frac_natural_gas * pollution_control_costs_per_kW * wage_scale)),
		real_opex_per_kW_start = starts_adj +  (gas_starts_adj * natural_gas_fraction) + 
		# real_opex_per_kW_start = starts_adj +  (gas_starts_adj * fuel_frac_natural_gas) + 
			(oil_starts_adj * petroleum_fraction),
			# (oil_starts_adj * fuel_frac_petroleum),
		real_fixed_opex_per_kW_age_coeff = age_obs_fixed_adj * wage_scale
	) %>%
	# Calculate estimated real variable costs opex, again breaking out coefficients dependent on age of observation
	# only for historical cost estimation
	mutate(real_variable_opex_per_MWh_est = (
			(gen_adj * wage_scale) +
				# (median_CF_adj * median_CF * wage_scale ) +
				# (high_median_CF_adj * high_median_CF * wage_scale ) +
				# (mid_median_CF_adj * mid_median_CF * wage_scale ) +
				# (low_median_CF_adj * low_median_CF * wage_scale ) +
				(oil_variable_adj * petroleum_fraction * wage_scale) +
				# (oil_variable_adj * fuel_frac_petroleum * wage_scale) +
				(pollution_variable_adj * pollution_control_costs_per_kw * wage_scale) +
				# (pollution_variable_adj * pollution_control_costs_per_kW * wage_scale) +
				(age_variable_adj * age_relative_to_prime_avg * wage_scale) +
				# (age_variable_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
				(fluidized_bed_variable_adj * fluidized_bed_tech * wage_scale) +
				# (fluidized_bed_variable_adj * fluidized_bed * wage_scale) +
				(CHP_variable_adj * associated_combined_heat_power * wage_scale) +
				# (CHP_variable_adj * chp * wage_scale) +
				(supercritical_variable_adj * supercritical_tech * wage_scale) +
				# (supercritical_variable_adj * supercritical * wage_scale) +
				(gas_age_variable_adj * natural_gas_fraction * age_relative_to_prime_avg * wage_scale) +
				# (gas_age_variable_adj * fuel_frac_natural_gas * diff_age_and_avg_plant_prime_fuel * wage_scale) +
				(duct_burners_variable_adj * duct_burners * wage_scale) +
				(oil_age_variable_adj * petroleum_fraction * age_relative_to_prime_avg * wage_scale)),
				# (oil_age_variable_adj * fuel_frac_petroleum * diff_age_and_avg_plant_prime_fuel * wage_scale)),
			real_variable_opex_per_MWh_age_coeff = (age_obs_variable_adj * wage_scale)
		)












