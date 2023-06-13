# Power Plant Characteristics
# 3_linear_regressions_on_opex
# 2023 April Andrew Bartnof
# Recreate Uday's linear regression models, and create alternate models
# - null model
# - legacy lm
# - legacy lm with log-transformed dv
# - glmer (gamma distribution, random effects for prime_mover:plant)
# Diagnostics:
# - group by whether the model is fitted on the data or training data
# - distribution of residuals
# - RMSE

library(conflicted)
library(skimr)
library(tidyverse)
library(lme4)
library(mclust)
# library(randomForest)
library(Metrics)
library(ggridges)
conflict_prefer('select', 'dplyr')
conflict_prefer('filter', 'dplyr')
conflict_prefer('map2', 'purrr')
conflict_prefer('map', 'purrr')
setwd('~/Documents/rmi/power_plant_characteristics/')
set.seed(1)

#### Define functions ####
get_ivs <- function(ff){
	# Input a formula, ff, and export a list of all IVs
	variables_to_keep <- unlist(str_extract_all(ff, '[A-Za-z_]+'))
	variables_to_keep_adj <- variables_to_keep[variables_to_keep != 'real_opex']
	return(variables_to_keep_adj)
}

get_variables_with_sd <- function(X){
	# Input a dataframe, export list of all numeric variables with variance
	X %>%
		drop_na %>%
		select_if(is.numeric) %>%
		sapply(., sd) %>%
		enframe('variable', 'sd') %>%
		filter(sd > 0) %>%
		pull(variable)
}

#### Establish data/variables ####
Data <- read_rds('clean_data/Data.RDS')
CCopex <- read_rds('clean_data/ccopex.RDS')
STopex <- read_rds('clean_data/stopex.RDS')
GTopex <- read_rds('clean_data/gtopex.RDS')

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
		~primary_mover, ~text,
		'CC', formula_ccopex,
		'GT', formula_gtopex,
		'ST', formula_stopex
	)

# FormulasLMER <-
# 	FormulasLM %>%
# 	mutate(text = as.character(text),
# 				 text = str_c(text, ' + (1|plant_id_eia)'),
# 				 text = map(text, as.formula))

#

#### Cluster: CCopex ####
variables_to_keep_adj <- get_ivs(formula_ccopex)
variables_with_sd <- get_variables_with_sd(CCopex)

X <-
	CCopex %>%
	drop_na %>%
	select(all_of(intersect(variables_to_keep_adj, variables_with_sd))) %>%
	mutate_all(~as.vector(scale(.)))

cls_cc <- Mclust(data = X, G = seq(1:9))
cls_cc$G
cls_cc$modelName
mod_cc <- Mclust(data = X, G = cls_cc$G, modelNames = cls_cc$modelName)

ClsCCopex <-
	CCopex %>%
	drop_na %>%
	bind_cols(cls = mod_cc$classification) %>%
	mutate(cls = factor(cls, ordered = F))

#### Cluster: STopex ####
variables_to_keep_adj <- get_ivs(formula_stopex)
variables_with_sd <- get_variables_with_sd(STopex)
X <-
	STopex %>%
	drop_na %>%
	select(all_of(intersect(variables_to_keep_adj, variables_with_sd))) %>%
	mutate_all(~as.vector(scale(.)))

cls_st <- Mclust(data = X, G = seq(1:9))
cls_st
mod_st <- Mclust(data = X, G = cls_st$G, modelNames = cls_st$modelName)
CLSSTopex <-
	STopex %>%
	drop_na %>%
	bind_cols(cls = mod_st$classification) %>%
	mutate(cls = factor(cls, ordered = F))

#### Cluster: GTopex ####
variables_to_keep_adj <- get_ivs(formula_gtopex)
variables_with_sd <- get_variables_with_sd(GTopex)
X <-
	GTopex %>%
	drop_na %>%
	select(all_of(intersect(variables_to_keep_adj, variables_with_sd))) %>%
	mutate_all(~as.vector(scale(.)))
cls_gt <- Mclust(data = X, G = seq(1:9))
cls_gt
mod_gt <- Mclust(data = X, G = cls_gt$G, modelNames = cls_gt$modelName)
CLSGTopex <-
	GTopex %>%
	drop_na %>%
	bind_cols(cls = mod_gt$classification) %>%
	mutate(cls = factor(cls, ordered = F))


# Nest all data, fit LMs, see if new categories help resolve
# variance

ModelledLM <-
	bind_rows(CLSGTopex, CLSSTopex, ClsCCopex) %>%
	mutate(cls = 'Original') %>%
	bind_rows(CLSGTopex, CLSSTopex, ClsCCopex) %>%
	group_by(prime_mover, cls) %>%
	nest %>%
	left_join(FormulasLM, by = c('prime_mover' = 'primary_mover')) %>%
	rename(formula = text) %>%
	mutate(
		mod = map2(data, formula, ~lm(data = .x, formula = .y)),
		y_true = map(data, 'real_opex'),
		y_fit = map(mod, predict)
	) %>%
	ungroup %>%
	select(prime_mover, cls, y_fit, y_true) %>%
	mutate(model_name = 'Linear regression',
				 cls_2 = if_else(cls == 'Original', 'Original', 'Clustered'))

ModelledLM %>%
	filter(cls == 'Original') %>%
	
	ModelledQuasipoisson <-
	bind_rows(CLSGTopex, CLSSTopex, ClsCCopex) %>%
	mutate(cls = 'Original') %>%
	bind_rows(CLSGTopex, CLSSTopex, ClsCCopex) %>%
	group_by(prime_mover, cls) %>%
	nest %>%
	left_join(FormulasLM, by = c('prime_mover' = 'primary_mover')) %>%
	rename(formula = text) %>%
	mutate(
		variables_with_sd = map(data, get_variables_with_sd),
		variables_iv = map(formula, get_ivs),
		variables_to_select = map2(variables_with_sd, variables_iv, intersect),
		variables_to_select = map(variables_to_select, ~c('real_opex', .)),
		data = map2(data, variables_to_select, select),
		mod = map(data, ~glm(data = ., formula = 'real_opex ~ .', family = quasipoisson())),
		y_fit = map(mod, predict, type='response'),
		y_true = map(data, 'real_opex')
	) %>%
	ungroup %>%
	select(prime_mover, cls, y_fit, y_true) %>%
	mutate(model_name = 'Quasipoisson',
				 cls_2 = if_else(cls == 'Original', 'Original', 'Clustered'))

#### diagnostics ####
ModStats <-
	bind_rows(ModelledLM, ModelledQuasipoisson) %>%
	select(-cls) %>%
	unnest(c(y_fit, y_true)) %>%
	group_by(model_name, prime_mover, cls_2) %>%
	summarize(prop_y_fit_neg = mean(y_fit < 0),
						RMSE = rmse(y_true, y_fit)) %>%
	ungroup

#### diagnostics 1: RMSE ####
ModStats %>%
	ggplot(aes(x = prime_mover, fill = cls_2, group = cls_2,
						 y = RMSE)) +
	geom_col(position = 'dodge') +
	facet_wrap(~model_name) +
	scale_fill_manual(values = c('dodgerblue', 'grey40')) +
	scale_y_continuous(labels = scales::comma_format()) +
	theme(legend.position = 'bottom',
				axis.ticks = element_blank(),
				panel.grid.major.x = element_blank()) +
	labs(x = '', y = 'RMSE', fill = 'Clustering')

ModStats %>%
	ggplot(aes(x = prime_mover, fill = cls_2, group = cls_2,
						 y = prop_y_fit_neg)) +
	geom_col(position = 'dodge') +
	facet_wrap(~model_name) +
	scale_fill_manual(values = c('dodgerblue', 'grey40')) +
	scale_y_continuous(labels = scales::percent_format()) +
	theme(legend.position = 'bottom',
				axis.ticks = element_blank(),
				panel.grid.major.x = element_blank()) +
	labs(x = '', y = 'Negative fitted values', fill = 'Clustering')

#### Examine cluster centroids ####

cls_cc$parameters[['mean']] %>%
	as.data.frame %>%
	rownames_to_column('variable') %>%
	gather(cluster, value, -variable) %>%
	mutate(cluster = str_extract(cluster, '[0-9]+')) %>%
	ggplot(aes(y = variable, x = value, color = cluster)) +
	geom_point() +
	geom_vline(xintercept = 0, linetype = 'dashed') +
	coord_cartesian(xlim = c(-1, 1)) +
	scale_y_discrete(limits = rev) +
	theme(
		axis.ticks = element_blank()
	) +
	labs(x = 'Cluster centroids (standard deviations)', y = 'Predictors',
			 title = 'CC', color = 'Cluster')

cls_st$parameters[['mean']] %>%
	as.data.frame %>%
	rownames_to_column('variable') %>%
	gather(cluster, value, -variable) %>%
	mutate(cluster = str_extract(cluster, '[0-9]+')) %>%
	ggplot(aes(y = variable, x = value, color = cluster)) +
	geom_point() +
	geom_vline(xintercept = 0, linetype = 'dashed') +
	coord_cartesian(xlim = c(-1, 1)) +
	scale_y_discrete(limits = rev) +
	theme(
		axis.ticks = element_blank()
	) +
	labs(x = 'Cluster centroids (standard deviations)', y = 'Predictors',
			 title = 'ST', color = 'Cluster')

cls_gt$parameters[['mean']] %>%
	as.data.frame %>%
	rownames_to_column('variable') %>%
	gather(cluster, value, -variable) %>%
	mutate(cluster = str_extract(cluster, '[0-9]+')) %>%
	ggplot(aes(y = variable, color = cluster)) +
	geom_point(aes(x = value)) +
	geom_vline(xintercept = 0, linetype = 'dashed') +
	expand_limits(x = -1) +
	scale_y_discrete(limits = rev) +
	theme(
		axis.ticks = element_blank()
	) +
	labs(x = 'Cluster centroids (standard deviations)', y = 'Predictors',
			 title = 'GT', color = 'Cluster')










