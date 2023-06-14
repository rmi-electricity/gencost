# Final work with coefficients
# 1. get all the regression variables ready; get PCA scores; weight PCA scores;
# put into cluster
# 2. Run final metric transformations

library(tidyverse)
library(skimr)
library(conflicted)
library(broom)
library(arrow)
library(lubridate)
library(flexclust)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

get_variables_with_variance <- function(X){
	X %>%
		select_if(is_numeric) %>%
		sapply(., var) %>%
		enframe('variable', 'var') %>%
		filter(is.finite(var), var > 0) %>%
		pull(variable)
	}

NestedPcaMods <- readRDS('clean_data/nested_pca_mods.RDS')
VarianceExplainedPerComponent <- read_csv('clean_data/variance_explained_per_component.csv')
Data <- read_csv('clean_data/data.csv')

# Clusters <- readRDS('clean_data/clusters')

# ClusteredData <- read_csv('clean_data/clustered_data.csv', col_types = c(
# 	prime_mover = 'c', plant_id_eia = 'f', cluster = 'f', 
# 	consolidated_regression_filter = 'l', .default = 'd'))

# Data <- read_csv('clean_data/data.csv', col_types = c(
# 	prime_mover = 'c', plant_id_eia = 'f',
# 	consolidated_regression_filter = 'l', .default = 'd'))

# Mods <- readRDS('clean_data/mods.RDS')

HistoricRaw <- read_parquet('input_data/historic_data_gen_level.parquet')
variables_for_regressions <- readRDS('clean_data/variables_for_regressions.RDS')
variables_for_clusters <- readRDS('clean_data/variables_for_clusters.RDS')

Historic <-
	HistoricRaw %>%
		mutate(
			capacity_adj = wage_scale * capacity_mw,
			age_fixed_adj = age_relative_to_prime_avg * capacity_adj,
			age_obs_fixed_adj = age_of_observation * capacity_adj,
			report_year = lubridate::year(report_date),
			duct_burners_fixed_adj = duct_burners * capacity_adj,
			starts_adj = generator_starts * capacity_adj,
			supercritical_fixed_adj = supercritical_tech * capacity_adj,
			CHP_fixed_adj = associated_combined_heat_power * capacity_adj,
			gen = gross_cf * capacity_mw * ifelse(report_year %% 4 ==0,8784,8760),
			gen_adj = wage_scale * gen,
			age_obs_variable_adj = age_of_observation * gen_adj,
			age_variable_adj = age_relative_to_prime_avg * gen_adj,
			fluidized_bed_variable_adj = fluidized_bed_tech * gen_adj,
			gas_age_fixed_adj = natural_gas_fraction * age_relative_to_prime_avg * capacity_adj,
			gas_age_variable_adj = natural_gas_fraction * age_relative_to_prime_avg * gen_adj,
			gas_fixed_adj = natural_gas_fraction * capacity_adj,
			gas_starts_adj = natural_gas_fraction * starts_adj,
			gas_pollution_fixed_adj = natural_gas_fraction * real_pollution_control_costs_per_kw * capacity_adj,
			oil_age_fixed_adj = petroleum_fraction * age_relative_to_prime_avg * capacity_adj,
			oil_fixed_adj = petroleum_fraction * capacity_adj,
			oil_starts_adj = petroleum_fraction * starts_adj,
			pollution_fixed_adj = real_pollution_control_costs_per_kw * capacity_adj,
			pollution_variable_adj = real_pollution_control_costs_per_kw * gen_adj,
			supercritical_variable_adj = supercritical_tech * gen_adj,
			CHP_variable_adj = associated_combined_heat_power * gen_adj,  # for final manipulations
			oil_age_variable_adj = petroleum_fraction * age_relative_to_prime_avg * gen_adj,
			pulverized_coal_fixed_adj = pulverized_coal_tech * capacity_adj,
			oil_variable_adj = petroleum_fraction * gen_adj
		) %>%
	rowid_to_column

# Run through the clustering with just one type of data
# X <-
# Step 1: using the original data; PCA; scale and weight; get clusters
variables_with_variance <-
	Data %>%
		filter(prime_mover == 'CC') %>%
		get_variables_with_variance
variables_to_select <- intersect(variables_with_variance, variables_for_clusters)

X <-
	Data %>%
		filter(prime_mover == 'CC') %>%
		select(all_of(variables_to_select))
R <- cor(X, method = 's', use = 'pairwise.complete.obs')
pca_fit <- psych::pca(r = R, nfactors = 3L, n.obs = nrow(X))
ProportionExplained <-
	pca_fit$Vaccounted %>%
		as.data.frame %>%
		rownames_to_column('metric') %>%
		filter(metric == 'Proportion Explained') %>%
		select(-metric) %>%
		gather(component, proportion_explained)
XScores <- psych::predict.psych(object = pca_fit, data = X, new.data = X)
XWeightedScaledScores <-
	XScores %>%
		as.data.frame %>%
		as_tibble %>%
		rowid_to_column %>%
		gather(component, score, -rowid) %>%
		group_by(component) %>%
		mutate(score_scaled = as.vector(scale(score))) %>%
		ungroup %>%
		left_join(ProportionExplained) %>%
		mutate(weighted_scaled_score = proportion_explained * score_scaled) %>%
		select(rowid, component, weighted_scaled_score) %>%
		spread(component, weighted_scaled_score)
# Now prepare the new data in the same way. Scale this data acc'd to the original
# data's parameters
Y <-
	Historic %>%
		filter(prime_mover == 'CC') %>%
		select(variables_to_select)
YRowIds <-
	Historic %>%
		filter(prime_mover == 'CC') %>%
		select(rowid)
XMeanAndSd <-
	XScores %>%
		as.data.frame %>%
		as_tibble %>%
		gather(component, value) %>%
		group_by(component) %>%
		summarize(mean = mean(value), sd = sd(value)) %>%
		ungroup
Yscores <- psych::predict.psych(object = pca_fit, data = Y, old.data = X)	
YWeightedScaledScores <-
	Yscores %>%
		as.data.frame %>%
		as_tibble %>%
		bind_cols(YRowIds) %>%
		gather(component, score, -rowid) %>%
		left_join(XMeanAndSd, by = 'component') %>%
		mutate(scaled_score = (score - mean)/sd) %>%
		left_join(ProportionExplained, by = 'component') %>%
		mutate(weighted_scaled_score = scaled_score * proportion_explained) %>%
		select(rowid, component, weighted_scaled_score) %>%
		spread(component, weighted_scaled_score)
# https://stackoverflow.com/questions/20621250/simple-approach-to-assigning-clusters-for-new-data-after-k-means-clustering
kmeans_fit <- kmeans(XWeightedScaledScores, 4)
# kmeans_fit <- kcca(x = XWeightedScaledScores, k = 4, kccaFamily("kmeans"))
y_cls <- predict(kmeans_fit, YWeightedScaledScores)
#



Y <-
	Historic %>%
		filter(prime_mover == 'CC') %>%
		select(variables_to_select)

Scores <- psych::predict.psych(object = pca_fit, data = Y, old.data = X)
Weights <-
	pca_fit$Vaccounted %>%
		as.data.frame %>%
		rownames_to_column('measure') %>%
		filter(measure == 'Proportion Explained') %>%
		select(-measure) %>%
		as.matrix
#


#
NestedPcaMods %>%
	left_join(OldData, by = 'prime_mover') %>%
	left_join(NewData, by = 'prime_mover') %>%
	mutate(
		old_data = map(old_data, as.matrix),
		new_data = map(new_data, as.matrix),
		scores = pmap(list(data = new_data, old.data = old_data, object = pca_fit), psych::predict.psych)
	)
	print
#



# Merge coefficients with historic data
Coefficients <-
	Mods %>%
		mutate(
			coefficients = map(lm_fit, 'coefficients'),
			coefficients = map(coefficients, as.data.frame),
			coefficients = map(coefficients, rownames_to_column),
			) %>%
		select(prime_mover, coefficients) %>%
		unnest(coefficients) %>%
		rename('variable' = rowname, 'value' = 3) %>%
		spread(variable, value)

# python_inputs_data_hist <- 
	Historic %>%
		inner_join(Coefficients, by = 'prime_mover') %>%
	mutate(
		real_fixed_opex_per_kW_no_starts_est = ( 
			(capacity_adj * wage_scale) + 
			# (median_CF_fixed_adj * median_CF * wage_scale ) +
			# (high_median_CF_fixed_adj * high_median_CF * wage_scale ) +
			# (mid_median_CF_fixed_adj * mid_median_CF * wage_scale ) +
			# (low_median_CF_fixed_adj * low_median_CF * wage_scale ) +
			(gas_fixed_adj * fuel_frac_natural_gas * wage_scale) + 
			(oil_fixed_adj * fuel_frac_petroleum * wage_scale) +
			(CHP_fixed_adj * chp * wage_scale) +
			(pollution_fixed_adj * pollution_control_costs_per_kW * wage_scale) +
			(pulverized_coal_fixed_adj * pulverized_coal * wage_scale) +
			(duct_burners_fixed_adj * duct_burners * wage_scale) +
			(supercritical_fixed_adj * supercritical * wage_scale) +
			(age_fixed_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
			(oil_age_fixed_adj * diff_age_and_avg_plant_prime_fuel * fuel_frac_petroleum * wage_scale) +
			(gas_pollution_fixed_adj * fuel_frac_natural_gas * pollution_control_costs_per_kW * wage_scale)),
		real_opex_per_kW_start = starts_adj +  (gas_starts_adj * fuel_frac_natural_gas) + 
			(oil_starts_adj * fuel_frac_petroleum),
		real_fixed_opex_per_kW_age_coeff = age_obs_fixed_adj * wage_scale
	)



	
	
str1 <- "	
	(capacity_adj * wage_scale) + 
		(gas_fixed_adj * fuel_frac_natural_gas * wage_scale) + 
		(oil_fixed_adj * fuel_frac_petroleum * wage_scale) +
		(CHP_fixed_adj * chp * wage_scale) +
		(pollution_fixed_adj * pollution_control_costs_per_kW * wage_scale) +
		(pulverized_coal_fixed_adj * pulverized_coal * wage_scale) +
		(duct_burners_fixed_adj * duct_burners * wage_scale) +
		(supercritical_fixed_adj * supercritical * wage_scale) +
		(age_fixed_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
		(oil_age_fixed_adj * diff_age_and_avg_plant_prime_fuel * fuel_frac_petroleum * wage_scale) +
		(gas_pollution_fixed_adj * fuel_frac_natural_gas * pollution_control_costs_per_kW * wage_scale)),
starts_adj +  (gas_starts_adj * fuel_frac_natural_gas) + 
	(oil_starts_adj * fuel_frac_petroleum),
age_obs_fixed_adj * wage_scale"
str2 <- "(gen_adj * wage_scale) +
      (median_CF_adj * median_CF * wage_scale ) +
      (high_median_CF_adj * high_median_CF * wage_scale ) +
      (mid_median_CF_adj * mid_median_CF * wage_scale ) +
      (low_median_CF_adj * low_median_CF * wage_scale ) +
      (oil_variable_adj * fuel_frac_petroleum * wage_scale) +
      (pollution_variable_adj * pollution_control_costs_per_kW * wage_scale) +
      (age_variable_adj * diff_age_and_avg_plant_prime_fuel * wage_scale) +
      (fluidized_bed_variable_adj * fluidized_bed * wage_scale) +
      (CHP_variable_adj * chp * wage_scale) +
      (supercritical_variable_adj * supercritical * wage_scale) +
      (gas_age_variable_adj * fuel_frac_natural_gas * diff_age_and_avg_plant_prime_fuel * wage_scale) +
      (duct_burners_variable_adj * duct_burners * wage_scale) +
      (oil_age_variable_adj * fuel_frac_petroleum * diff_age_and_avg_plant_prime_fuel * wage_scale)),
    (age_obs_variable_adj * wage_scale) ) "

c(str1, str2) %>%
	enframe(name = NULL, value = 'text') %>%
	mutate(token = str_extract_all(text, '[A-Za-z0-9_]+')) %>%
	unnest(token) %>%
	distinct(token) %>%
	arrange(token) %>%
	mutate(is_in_hist = token %in% colnames(Historic),
				 is_regression_variable = token %in% variables_for_regressions,
				 is_median_cf = str_detect(token, 'median_CF')
  ) %>%
	filter(!is_in_hist & !is_regression_variable & !is_median_cf)
# fuel_frac_natural_gas

Historic$supercritical_tech
