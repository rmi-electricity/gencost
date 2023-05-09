# Power Plant Characteristics
# 4_glm
# 2023 April Andrew Bartnof

# Goal: Fit a GLM to properly model real_opex_per_kw 
# Overall: 
#- fit log-transformed lm 
#- fit log-transformed lm with interactions
#- fit log-transformed lm per prime mover
#- fit log-transformed lm per prime mover with interactions
#- fit random forest

library(tidyverse)
library(dotwhisker)
library(lme4)
library(skimr)
library(conflicted)
conflict_prefer('select', 'dplyr')
conflict_prefer('filter', 'dplyr')
setwd('~/Documents/rmi/power_plant_characteristics/')
Data <- readRDS('clean_data/Data.RDS')

get_significant_variables <- function(mod){
	# Pull a list of variables from a model whose 95%CI don't include 0
	mod %>%
		confint %>%
		as.data.frame %>%
		rownames_to_column('variable') %>%
		as_tibble %>%
		drop_na %>%
		rename(low = `2.5 %`, high = `97.5 %`) %>%
		mutate(is_ci_implausible = low < 0 & high > 0) %>%
		filter(!is_ci_implausible) %>%
		pull(variable)
}

#### Look at the DV distribution, exclude outliers ####
low_and_high <-
	Data %>%
		select(real_opex_per_kw) %>%
		drop_na %>%
		pull %>%
		quantile(c(0.025, 0.975))

xx <-
	Data %>%
		select(real_opex_per_kw) %>%
		drop_na %>%
		filter(real_opex_per_kw >= low_and_high[[1]], 
					 real_opex_per_kw <= low_and_high[[2]]) %>%
		pull

Data %>%
	select(real_opex_per_kw, prime_mover) %>%
	drop_na %>%
	filter(real_opex_per_kw >= low_and_high[[1]], 
				 real_opex_per_kw <= low_and_high[[2]]) %>%
	ggplot(aes(x = real_opex_per_kw)) +
	geom_histogram() +
	facet_wrap(~prime_mover)

# It looks like the three kinds of prime_mover have pretty distinct gamma distributions.
# In the future, fit 3 models based on central 95% of data

CleanData <-	
	Data %>%
		drop_na(real_opex_per_kw, prime_mover) %>%
		filter(real_opex_per_kw >= low_and_high[[1]], 
					 real_opex_per_kw <= low_and_high[[2]]) %>%
	select(-fluidized_bed_tech, -rmi_fuel_group_1, -rmi_fuel_group_2, 
				 -rmi_fuel_group_3, -fuel_category
				 ) %>%
	mutate_at('report_date', as.numeric)

variables_to_scale <-
	CleanData %>%
		select_if(is.numeric) %>%
		colnames 

variables_to_scale <- variables_to_scale[variables_to_scale != 'real_opex_per_kw']

CleanData <-
	CleanData %>%
		mutate_at(all_of(variables_to_scale), ~as.vector(scale(.)))

####- fit log-transformed lm ####
# strategy: it's easier to be agnostic to variables with a lm than a glm,
# because there's fewer power issues- consequently, we'll immitate a glm by
# modeling the log-transformed DV in lieu of a gamma distribution in the glm

mod <- lm(data = CleanData, formula = log(real_opex_per_kw) ~ .)



significant_variables <-
	confint(mod) %>%
		as.data.frame %>%
		rownames_to_column('variable') %>%
		as_tibble %>%
		rename(low = `2.5 %`, high = `97.5 %`) %>%
		drop_na %>%
		mutate(is_ci_implausible = low < 0 & high > 0) %>%
		filter(!is_ci_implausible) %>%
		pull(variable)

colnames(CleanData)[colnames(CleanData) %in% significant_variables]
# glm doesn't need pollution_control_costs_per_kw
me_mod_overall_no_interactions <- glmer(data = CleanData, family = Gamma(),
	formula = real_opex_per_kw ~ average_age_in_report_year + 
		bypass_heat_recovery + generator_starts + gross_cf + gross_generation_mwh + 
		pulverized_coal_tech + report_date + (1|prime_mover:plant_id_eia)
)
summary(me_mod_overall_no_interactions)

#- fit log-transformed lm with interactions
TempData <-
	CleanData %>%
		select(-plant_id_eia, -sector, -final_gen_type)

mod <- lm(data = TempData, formula = log(real_opex_per_kw) ~ (.)^2)

mod %>% get_significant_variables()

me_mod_overall_with_interactions <- glmer(data = CleanData, family = Gamma(),
	formula = real_opex_per_kw ~ 
		pulverized_coal_tech * supercritical_tech +
		pollution_control_costs_per_kw * supercritical_tech +
		pollution_control_costs_per_kw * subcritical_tech +
		pollution_control_costs_per_kw * pulverized_coal_tech +
		other_combustion_tech * pulverized_coal_tech +
		other_combustion_tech * pollution_control_costs_per_kw +
		gross_generation_mwh * supercritical_tech +
		gross_generation_mwh * subcritical_tech +
		gross_generation_mwh * pulverized_coal_tech +
		gross_cf * supercritical_tech +
		gross_cf * subcritical_tech +
		generator_starts * pollution_control_costs_per_kw +
		duct_burners * gross_generation_mwh +
		duct_burners * generator_starts +
		average_age_in_report_year * gross_cf +
		average_age_in_report_year * gross_generation_mwh +
		average_age_in_report_year * pulverized_coal_tech +
		associated_combined_heat_power * pulverized_coal_tech +
		associated_combined_heat_power * bypass_heat_recovery +
		report_date +
		(1|prime_mover:plant_id_eia)
)

me_mod_overall_with_interactions
#

#- fit log-transformed lm per prime mover
#- fit log-transformed lm per prime mover with interactions
#- fit random forest