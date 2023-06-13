# Power Plant Characteristics
# 3_linear_regressions_on_opex
# 2023 April Andrew Bartnof
# Recreate Uday's linear regression models, and create alternate models
# - legacy lm
# - glmer (gamma distribution, random effects for prime_mover:plant)
# Diagnostics:
# - group by whether the model is fitted on the data or training data
# - distribution of residuals
# - RMSE

library(conflicted)
library(skimr)
library(tidyverse)
# library(Metrics)
conflict_prefer('select', 'dplyr')
conflict_prefer('filter', 'dplyr')
conflict_prefer('map2', 'purrr')
conflict_prefer('map', 'purrr')
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')
set.seed(1)

#### Define functions ####
get_variables_with_sd <- function(X){
	# Input a dataframe, export list of all numeric variables with variance
	X %>%
		select_if(is.numeric) %>%
		sapply(., sd, na.rm = T) %>%
		enframe(name = 'variable', value = 'sd') %>%
		filter(is.finite(sd), sd > 0) %>%
		pull(variable)
}

#### Establish data/variables ####
Data <- read_rds('clean_data/Data.RDS')
CCopex <- read_rds('clean_data/ccopex.RDS')
STopex <- read_rds('clean_data/stopex.RDS')
GTopex <- read_rds('clean_data/gtopex.RDS')
ClsOptions <- readRDS('clean_data/cls_options.RDS')

# Legacy model
formula_stopex <- as.formula('
real_opex ~ 0 + CHP_variable_adj + age_obs_variable_adj + age_variable_adj +
capacity_adj + fluidized_bed_variable_adj + gas_age_fixed_adj + 
gas_age_variable_adj + gas_fixed_adj + gas_pollution_fixed_adj + 
gas_starts_adj + gen_adj + high_median_CF_adj + high_median_CF_fixed_adj + 
median_CF_adj + median_CF_fixed_adj + mid_median_CF_adj + 
mid_median_CF_fixed_adj + oil_fixed_adj +pollution_fixed_adj + 
pollution_variable_adj + pulverized_coal_fixed_adj + starts_adj + 
supercritical_fixed_adj + supercritical_variable_adj
')

formula_ccopex <- as.formula('
real_opex ~ 0 + chp_fixed_adj + age_obs_variable_adj + age_variable_adj +
capacity_adj + duct_burners_fixed_adj + gen_adj + high_median_CF_adj +
high_median_CF_fixed_adj + low_median_CF_adj + low_median_CF_fixed_adj +
median_CF_adj + median_CF_fixed_adj + mid_median_CF_adj + 
mid_median_CF_fixed_adj + oil_age_fixed_adj + pollution_variable_adj +
starts_adj
')

formula_gtopex <- as.formula(
'real_opex ~ 0 + age_fixed_adj + age_obs_fixed_adj + age_obs_variable_adj +
age_variable_adj + capacity_adj + gen_adj + high_median_CF_adj + 
low_median_CF_adj + low_median_CF_fixed_adj + median_CF_adj + 
median_CF_fixed_adj + mid_median_CF_adj + mid_median_CF_fixed_adj + 
oil_age_fixed_adj + oil_fixed_adj + oil_starts_adj + oil_variable_adj + 
starts_adj
')

FormulasLM <-
	tribble(
		~prime_mover, ~text,
		'CC', formula_ccopex,
		'GT', formula_gtopex,
		'ST', formula_stopex
	)

#
JoinmeGrouped <-
	bind_rows(CCopex, GTopex, STopex) %>%
	left_join(ClsOptions, by = c("rowid", "prime_mover")) %>%
	group_by(prime_mover, num_clusters, cls) %>%
	nest %>%
	ungroup

JoinmeAuNatural <-
	bind_rows(CCopex, GTopex, STopex) %>%
	group_by(prime_mover) %>%
	nest %>%
	ungroup

LmFit <-
	bind_rows(JoinmeGrouped, JoinmeAuNatural)	%>%
	mutate(
		num_clusters = factor(num_clusters, ordered = T),
		num_clusters = fct_explicit_na(num_clusters, na_level = 'Unclustered'),
		num_clusters = fct_relevel(num_clusters, 'Unclustered'),
		cls = factor(cls, ordered = T),
		cls = fct_explicit_na(cls, na_level = 'Unclustered'),
		cls = fct_relevel(cls, 'Unclustered'),
	) %>%
	left_join(FormulasLM, by = 'prime_mover') %>%
	mutate(
	lm_fit = map2(data, text, ~lm(data = .x, formula = .y))
	)

LmGof <-
	LmFit %>%
	mutate(
		residuals = map(lm_fit, 'residuals'),
		model_type = 'Linear Regression'
	) %>%
	select(-data, -text, -lm_fit) %>%
	unnest(residuals)

#	 GLM
VariablesToSelect <-
	# Note all of the variables each subset needs
	FormulasLM %>%
		mutate(
			text = as.character(text),
			tokens = str_extract_all(text, '[A-Za-z0-9_]+'),
			) %>%
		select(-text) %>%
		unnest(tokens) %>%
		filter(str_length(tokens) > 1) %>%
		distinct %>%
		nest(data = c(tokens)) %>%
		mutate(variables_to_select = map(data, pull)) %>%
		select(prime_mover, variables_to_select)

GlmFit <-
	bind_rows(JoinmeGrouped, JoinmeAuNatural)	%>%
	left_join(VariablesToSelect, by = 'prime_mover') %>%
	mutate(
		num_clusters = factor(num_clusters, ordered = T),
		num_clusters = fct_explicit_na(num_clusters, na_level = 'Unclustered'),
		num_clusters = fct_relevel(num_clusters, 'Unclustered'),
		cls = factor(cls, ordered = T),
		cls = fct_explicit_na(cls, na_level = 'Unclustered'),
		cls = fct_relevel(cls, 'Unclustered'),
		data = map2(data, variables_to_select, select),
	  variables_with_variance = map(data, get_variables_with_sd),
		data = map2(data, variables_with_variance, select),
		glm_fit = map(data, ~glm(data = ., formula = 'real_opex ~ 0 + .',
														family = poisson()))
	) %>%
	select(-variables_to_select, -variables_with_variance)
#
	GlmGof <-
		GlmFit %>%
			mutate(
				residuals = map(glm_fit, 'residuals')
			) %>%
			select(-data, -glm_fit) %>%
			unnest(residuals) %>%
		mutate(model_type = 'Poisson')
	
RMSE <-
	bind_rows(GlmGof, LmGof) %>%
	group_by(model_type, prime_mover, num_clusters, cls) %>%
	summarize(rmse = sqrt(mean(residuals**2))) %>%
	ungroup
#
RMSE %>%
ggplot(aes(x = num_clusters, group = cls, fill = cls, y = rmse)) +
	geom_col(position = 'dodge') +
	facet_grid(model_type ~ prime_mover, scale = 'free')
#


CCopex <-
	LmFit %>%
		filter(num_clusters == 'Unclustered', prime_mover == 'CC') %>%
		pull(lm_fit) %>%
		.[[1]]
STopex <-
	LmFit %>%
		filter(num_clusters == 'Unclustered', prime_mover == 'ST') %>%
		pull(lm_fit) %>%
		.[[1]]
GTopex <-
	LmFit %>%
		filter(num_clusters == 'Unclustered', prime_mover == 'GT') %>%
		pull(lm_fit) %>%
		.[[1]]
saveRDS(CCopex, file = 'clean_data/cc_opex_mod.RDS')
saveRDS(STopex, file = 'clean_data/st_opex_mod.RDS')
saveRDS(GTopex, file = 'clean_data/gt_opex_mod.RDS')
