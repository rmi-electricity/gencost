# Regression models
library(tidyverse)
library(skimr)
library(conflicted)
# library(Metrics)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')
Data <- read_csv('clean_data/data.csv', col_types = c(
	prime_mover = 'c', plant_id_eia = 'f', 
	consolidated_regression_filter = 'l', .default = 'd')) %>%
	filter(consolidated_regression_filter)  # regressions will be on filtered data.
ClusteredData <- readRDS('clean_data/clustered_data.RDS')
get_variable_names_with_variance <- readRDS('clean_data/get_variable_names_with_variance.RDS')
FormulasRealOpex <- read_csv('clean_data/formulas_real_opex.csv', col_types = 'cc')

#### 1. Get actual coefficients ####
# Add unclustered data to the top of the dataset


ModsFit <-
	ClusteredData %>%
		select(-prime_mover) %>%
		unnest(c(rowid, cluster)) %>%
		inner_join(Data, by = 'rowid') %>%
		# drop_na(real_opex) %>%
		select(-rowid) %>%
		group_by(prime_mover, num_clusters, cluster) %>%
		nest %>%
		ungroup %>%
		# bind_rows(JoinmeUnclustered) %>%
		left_join(FormulasRealOpex, by = 'prime_mover') %>%
		mutate(lm_fit = map2(formula, data, lm)) %>%
		select(prime_mover, num_clusters, cluster, lm_fit) %>%
		arrange(num_clusters, cluster, prime_mover)
print(ModsFit)

# Look at which variables are modelled
ModsFit %>%
	filter(num_clusters == 1L) %>%
	mutate(
		coefficients = map(lm_fit, 'coefficients'),
		coefficients = map(coefficients, as.data.frame),
		coefficients = map(coefficients, rownames_to_column),
		) %>%
	unnest(coefficients) %>%
	distinct(rowname) %>%
	arrange(rowname) %>%
	pull
	
NestedCoefficients <-
	ModsFit %>%
		mutate(
			coefficients = map(lm_fit, ~(summary(.))$coefficients),
			coefficients = map(coefficients, as.data.frame),
			coefficients = map(coefficients, rownames_to_column, 'measure'),
			coefficients = map(coefficients, select, c('measure', 'estimate' = 'Estimate', 'se' = 'Std. Error'))
			)
# print(NestedCoefficients)

#### 2. Plot measures of accuracy ####
CVGoF <-
	ClusteredData %>%
		select(-prime_mover) %>%
		unnest(c(rowid, cluster)) %>%
		inner_join(Data, by = 'rowid') %>%
		drop_na(real_opex) %>%
		group_by(prime_mover, num_clusters, cluster) %>%
		nest %>%
		ungroup %>%
		# bind_rows(JoinmeUnclustered) %>%  # unclustered for reference
		left_join(FormulasRealOpex, by = 'prime_mover') %>%
		expand_grid(boot_num = seq(1, 100)) %>%   # number of bootstraps
		mutate(
			Train = map(data, sample_frac, size = 0.75, replace = F),
			Test = map2(data, Train, anti_join, by = 'rowid'),
			lm_train = map2(formula, Train, lm),
			y_fit = map2(lm_train, Test, predict.lm, type = 'response'),
			y_true = map(Test, 'real_opex')
			) %>%
		# select(prime_mover, num_clusters, y_true, y_fit) %>%
		unnest(c(y_true, y_fit)) %>%
		mutate(
			residual = y_true - y_fit,
			residual2 = residual**2
		) %>%
		group_by(prime_mover, num_clusters, boot_num) %>%
		summarize(rmse = sqrt(mean(residual2))) %>%
		ungroup

CVGoF %>%
mutate(num_clusters = ordered(num_clusters)) %>%
	ggplot(aes(x = num_clusters, y = rmse)) +
	geom_boxplot() +
	coord_cartesian(ylim = c(0, 25000000)) +
	facet_wrap(~prime_mover) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.minor.x = element_blank(),
		text = element_text(family = 'serif')
	)

#### Save variables to disk ####
saveRDS(NestedCoefficients, 'clean_data/nested_coefficients.RDS')	
#### End here for now ####

temp <- lm(weight ~ feed, chickwts)
data.frame(
	resid = temp$residuals,
	y_fit = temp$fitted.values,
	y = chickwts$weight
) %>%
	as_tibble %>%
	print
#



# Test different regression models, cross-validated
ModsFit <-
	ClusteredData %>%
		mutate(cluster = '(None)') %>%
		bind_rows(ClusteredData) %>%
		select(rowid, prime_mover, cluster, all_of(variables_for_regressions)) %>%
		group_by(prime_mover, cluster) %>%
		nest %>%
		expand_grid(resample_i = seq(1, 20)) %>%
		mutate(
			# Train and test sets
			train = map(data, sample_frac, size = 0.75, replace = F),
			test = map2(data, train, anti_join, by = 'rowid'),
			# Remove non-regression variables
			train = map(train, select, -'rowid'),
			variables = map(train, get_variable_names_with_variance),
			train = map2(train, variables, select),
			# Fit models
			y_true = map(test, select, 'real_opex'),
			lm_fit = map(train, lm, formula = 'real_opex ~ 0 + .'),
			y_fit_lm = map2(lm_fit, test, predict),
			glm_fit = map(train, glm, formula = 'real_opex ~ 0 + .', family = poisson()),
			y_fit_glm = map2(glm_fit, test, predict, type = 'response')
		)

ModsFit %>%
	select(prime_mover, cluster, resample_i, y_true, y_fit_lm, y_fit_glm) %>%
	unnest(c(y_true, y_fit_lm, y_fit_glm)) %>%
	rename('Linear model' = y_fit_lm, 'Poisson' = y_fit_glm) %>%
	gather(mod_type, y_fit, -prime_mover, -cluster, -resample_i, -real_opex) %>%
	group_by(prime_mover, cluster, resample_i, mod_type) %>%
	summarize(rmse = Metrics::rmse(real_opex, y_fit)) %>%
	ungroup %>%
	group_by(prime_mover, cluster, mod_type) %>%
	summarize(avg_rmse = median(rmse),
						low = median(rmse) - sd(rmse),
						high = median(rmse) + sd(rmse)) %>%
	ungroup %>%
	ggplot(aes(x = prime_mover, y = avg_rmse, group = cluster, fill = cluster)) +
	geom_col(position = 'dodge') +
	# geom_segment(position = 'dodge', aes(xend = cluster, y = low, yend = high)) +
	facet_wrap(~mod_type, scales = 'free') +
	coord_cartesian(ylim = c(0, 1000000000)) +
	scale_y_continuous(labels = scales::comma_format()) +
	theme(
		axis.ticks = element_blank(),
		legend.position = 'bottom'
	) +
	labs(x = 'Cluster', y = 'Median RMSE', 
			 title = 'Goodness of fit', fill = 'Cluster')

ModsNotCv <-
	ClusteredData %>%
		mutate(cluster = '(None)') %>%
		bind_rows(ClusteredData) %>%
		select(prime_mover, cluster, all_of(variables_for_regressions)) %>%
		group_by(prime_mover, cluster) %>%
		nest %>%
		mutate(
			# Remove non-regression variables
			variables = map(data, get_variable_names_with_variance),
			data = map2(data, variables, select),
			# Fit models
			lm_fit = map(data, lm, formula = 'real_opex ~ 0 + .'),
			y_fit_lm = map2(lm_fit, data, predict),
			glm_fit = map(data, glm, formula = 'real_opex ~ 0 + .', family = poisson()),
			y_fit_glm = map2(glm_fit, data, predict, type = 'response')
		)

ModsNotCv %>%
	ungroup %>%
	select(prime_mover, cluster, 'Linear model' = y_fit_lm, 'Poisson' = y_fit_glm) %>%
	unnest(c('Linear model', 'Poisson')) %>%
	gather(mod_type, value, -prime_mover, -cluster) %>%
	mutate(is_y_fit_neg = value < 0) %>%
	group_by(prime_mover, cluster, mod_type) %>%
	summarize(prop_neg = mean(is_y_fit_neg)) %>%
	ungroup %>%
	ggplot(aes(x = prime_mover, y = prop_neg, fill = cluster, group = cluster)) +
	geom_col(position = 'dodge') +
	facet_wrap(~mod_type, nrow = 1) +
	scale_y_continuous(labels = scales::percent_format()) +
	theme(
		axis.ticks = element_blank(),
		legend.position = 'bottom') +
	labs(x = 'Prime mover', y = '% of negative fitted values', fill = 'Cluster')

Mods <-
	ModsNotCv %>%
		ungroup %>%
		filter(
			cluster == '(None)'
		) %>%
		select(prime_mover, cluster, lm_fit)

write_rds(Mods, 'clean_data/mods.RDS')	
