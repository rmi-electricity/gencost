# Regression models
library(tidyverse)
library(skimr)
library(broom)
library(conflicted)
# library(leaps)
# library(Metrics)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')

set.seed(1)	
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

ClustersFit <- readRDS('clean_data/clusters_fit.RDS')
CleanedDataBySubplant <- read_csv('clean_data/cleaned_data_by_subplant_data.csv')
CleanedHistoricalData <- read_csv('clean_data/cleaned_historical_data.csv')

LongVariableKey <- read_csv('clean_data/long_variable_key.csv', col_types = c(
	variable = 'c', .default = 'f'))

# Count variables
LongVariableKey %>%
	filter(variable_type != 'unused') %>%
	count(prime_mover, variable_type) %>%
	spread(variable_type, n) %>%
	mutate(subtotal = core + optional)

#### Fit the DataBySubplant dataset agnostically, and with core variables ####
# put core_variables in a list, per prime_mover
CoreVariables <-
	LongVariableKey %>%
		filter(variable_type == 'core') %>%
		select(prime_mover, variable) %>%
		nest(data = variable) %>%
		mutate(
			core_variables = map(data, pull),
		) %>%
		select(prime_mover, core_variables)

JoinmeCoreFormulas <-
	CoreVariables %>%
		mutate(
			concat_variables = map(core_variables, paste0, collapse = ' + '),
			formula = map(concat_variables, ~str_c('real_opex ~ 0 + ', .)),
			pull_size = 0L
		) %>%
		select(prime_mover, pull_size, formula) %>%
		unnest(formula)
print(as.data.frame(JoinmeCoreFormulas))

AllFormulas <-
	LongVariableKey %>%
		filter(variable_type == 'optional') %>%
		select(prime_mover, variable) %>%
		nest(data = variable) %>%
		mutate(
			data = map(data, pull),
			set_size = map_int(data, length),
			pull_size = map(set_size, ~seq(1, .)), # a sequence from 1 to the number of items in the set
	  ) %>%
		unnest(pull_size) %>%
		mutate(
			combination = map2(data, pull_size, combn, simplify = F),
		) %>%
		unnest(combination) %>%
		mutate(combination = map(combination, sort)) %>%  # makes it easier to read them later
		select(prime_mover, pull_size, optional_variables = combination) %>%
		left_join(CoreVariables, by = 'prime_mover') %>%
		mutate(
			combined_variables = map2(optional_variables, core_variables, c),
			concat_variables = map(combined_variables, paste0, collapse = ' + '),
			formula = map(concat_variables, ~str_c('real_opex ~ 0 + ', .))
			) %>%
		select(prime_mover, pull_size, formula) %>%
		unnest(formula) %>%
		bind_rows(JoinmeCoreFormulas) %>%
		arrange(prime_mover, pull_size)

AllFormulas %>%
	count(prime_mover)
AllFormulas %>%
	sample_n(4) %>%
	as.data.frame


#### Train and Test the models ####

TrainTest <-
	ClustersFit %>%
		select(prime_mover, rowid, cls) %>%
		unnest(c(rowid, cls)) %>%
		inner_join(CleanedDataBySubplant, by = c('prime_mover', 'rowid')) %>%
		group_by(prime_mover, cls) %>%
		nest %>%
		ungroup %>%
		mutate(
			nrow = map_int(data, nrow),
			indices = map(nrow, ~sample(x = seq(1, 3), size = ., replace = T)) # for resampling (will create 3 folds)
		) %>%
		expand_grid(boot_num = seq(1, 3)) %>% # using above resampling indices
		mutate(
			train_indices = map2(indices, boot_num, ~(.x != .y)),
			test_indices = map2(indices, boot_num, ~(.x == .y)),
			Train = map2(data, train_indices, filter),
			Test = map2(data, test_indices, filter)
		)

# Fan out by joining each train/test row to all of the prime mover's formulas
# Get fitted values and note RMSE
TrainFit <-
	TrainTest	 %>%
		inner_join(AllFormulas, by = 'prime_mover') %>%
		mutate(
			lm_fit = map2(formula, Train, lm),
		)

PredictedValues <-
	TrainFit %>%
		mutate(
			y_fit = map2(lm_fit, Test, predict.lm),
			y = map(Test, pull, 'real_opex')
		)

RMSE <-
	PredictedValues %>%
		unnest(c(y_fit, y)) %>%
		mutate(residual = y_fit - y) %>%
		group_by(prime_mover, cls, pull_size, formula, boot_num) %>%
		summarize(rmse = sqrt(mean(residual^2))) %>%
		ungroup

####
write_csv(RMSE, 'clean_data/all_models_rmse.csv')


#### Start here if you simply want to read extant RMSE data ####
RMSE <- read_csv('clean_data/all_models_rmse.csv', 
								 col_types = c(prime_mover = 'c', formula = 'c', cls = 'i', 
								 							pull_size = 'i', boot_num = 'i', rmse = 'd'))

####
# Get the smallest RMSE; in case of tie, prefer fewer variables
# (smaller pull_size)
MeanRMSE <-
	RMSE %>%
		group_by(prime_mover, cls, pull_size, formula) %>%
		summarize(
			mean_rmse = mean(rmse),
		) %>%
		ungroup %>%
		arrange(prime_mover, cls, mean_rmse, pull_size) %>%
		group_by(prime_mover, cls) %>%
		mutate(rank = row_number()) %>%
		ungroup
		
ChosenFormulas <-
	MeanRMSE %>%
		filter(rank == 1L) %>%
		select(prime_mover, cls, pull_size, formula, mean_rmse)
ChosenFormulas

# Fit mods to entire datasets 
# (this will allow us to then get F-tests and coefficients)
AllModsFit <-
	ClustersFit %>%
		select(prime_mover, rowid, cls) %>%
		unnest(c(rowid, cls)) %>%
		inner_join(CleanedDataBySubplant, by = c('prime_mover', 'rowid')) %>%
		group_by(prime_mover, cls) %>%
		nest %>%
		ungroup %>%
		inner_join(AllFormulas, by = 'prime_mover') %>%
		mutate(
			lm_fit = map2(formula, data, lm),
			summary_lm_fit = map(lm_fit, summary),
			coefficients = map(summary_lm_fit, 'coefficients'),
			coefficients = map(coefficients, as.data.frame),
			coefficients = map(coefficients, rownames_to_column, 'variable_name'),
		)


# Get fitted values from all mods for verification later
FittedValues <-
	AllModsFit %>%
		inner_join(ChosenFormulas, by = c('prime_mover', 'cls', 'pull_size', 'formula')) %>%
		mutate(
			fitted_values = map(lm_fit, 'fitted.values'),
			rowid = map(data, 'rowid'),
			) %>%
		select(prime_mover, cls, pull_size, formula, rowid, fitted_values) %>%
		unnest(c(rowid, fitted_values))

# Get coefficients from all mods
AllPossibleCoefficients <-
	AllModsFit %>%
		select(prime_mover, cls, pull_size, formula, coefficients) %>%
		unnest(coefficients) %>%
		rename(variable = variable_name, coefficient = Estimate) %>%
		left_join(LongVariableKey, by = c('prime_mover', 'variable')) %>%
		select(prime_mover, cls, pull_size, formula, variable, category, coefficient)

write_csv(AllPossibleCoefficients, 'clean_data/all_possible_coefficients.csv')
write_csv(ChosenFormulas, 'clean_data/chosen_formulas.csv')
write_csv(FittedValues, 'clean_data/fitted_values.csv')
write_csv(MeanRMSE, 'clean_data/mean_rmse.csv')

#### Appendix: reporting goodness of fit ####
# color scheme: water and rust
# https://color.adobe.com/explore

MeanRMSE %>%
	count(prime_mover, cls)

JoinmeIsChosen <-
	ChosenFormulas %>%
		mutate(is_chosen = TRUE)

MeanRMSE %>%
	filter(prime_mover == 'CC') %>%
	left_join(JoinmeIsChosen, by = c("prime_mover", "cls", "pull_size", "formula", "mean_rmse")) %>%
	mutate(is_chosen = replace_na(is_chosen, FALSE)) %>%
	arrange(is_chosen) %>%
	ggplot(aes(x = pull_size, y = mean_rmse)) +
	geom_smooth(method = 'lm', formula = y ~ poly(x, 3), se = T, color = '#151F30') +
	geom_point(aes(color = is_chosen)) +
	scale_color_manual(values = c('FALSE' = '#103778', 'TRUE' = '#E3371E')) +
	scale_y_continuous(labels = scales::comma_format(1)) +
	facet_wrap(~cls, scales = 'free_y') +
	theme(axis.ticks = element_blank(),
				legend.position = 'bottom',
				panel.grid.major.x = element_blank(),
				panel.grid.minor.x = element_blank(),
				text = element_text(family = 'serif')) +
	labs(x = 'Optional variables', y = 'Mean RMSE (lower is better)',
			 color = 'Model with the best fit',
			 title = 'Model goodness-of-fit, for each cluster',
			 caption = str_wrap('Each dataset was tested with cross-validation three times, with each training set consisting of 2/3 of the data. After attempting to predict the testing set\'s values three times, the resulting RMSE metrics were averaged; this is what is illustrated above. NB each y-axis uses a different scale.'),
			 subtitle = 'CC')

MeanRMSE %>%
	filter(prime_mover == 'GT') %>%
	left_join(JoinmeIsChosen, by = c("prime_mover", "cls", "pull_size", "formula", "mean_rmse")) %>%
	mutate(is_chosen = replace_na(is_chosen, FALSE)) %>%
	arrange(is_chosen) %>%
	ggplot(aes(x = pull_size, y = mean_rmse)) +
	geom_smooth(method = 'lm', formula = y ~ poly(x, 3), se = T, color = '#151F30') +
	geom_point(aes(color = is_chosen)) +
	scale_color_manual(values = c('FALSE' = '#103778', 'TRUE' = '#E3371E')) +
	scale_y_continuous(labels = scales::comma_format(1)) +
	facet_wrap(~cls, scales = 'free_y') +
	theme(axis.ticks = element_blank(),
				legend.position = 'bottom',
				panel.grid.major.x = element_blank(),
				panel.grid.minor.x = element_blank(),
				text = element_text(family = 'serif')) +
	labs(x = 'Optional variables', y = 'Mean RMSE (lower is better)',
			 color = 'Model with the best fit',
			 title = 'Model goodness-of-fit, for each cluster',
			 subtitle = 'GT',
			 caption = str_wrap('Each dataset was tested with cross-validation three times, with each training set consisting of 2/3 of the data. After attempting to predict the testing set\'s values three times, the resulting RMSE metrics were averaged; this is what is illustrated above. NB each y-axis uses a different scale.'))

MeanRMSE %>%
	filter(prime_mover == 'ST') %>%
	# left_join(JoinmeIsChosen, by = c("prime_mover", "cls", "pull_size", "formula", "mean_rmse")) %>%
	# mutate(is_chosen = replace_na(is_chosen, FALSE)) %>%
	# arrange(is_chosen) %>%
	ggplot(aes(x = pull_size, y = mean_rmse)) +
	geom_boxplot(alpha = 0.3, aes(x = ordered(pull_size))) +
	geom_point(data = filter(JoinmeIsChosen, prime_mover == 'ST'), color = '#E3371E') +
	# geom_smooth(method = 'lm', formula = y ~ poly(x, 3), se = T, color = '#151F30') +
	# geom_point(aes(color = is_chosen)) +
	scale_color_manual(values = c('FALSE' = '#103778', 'TRUE' = '#E3371E')) +
	scale_y_continuous(labels = scales::comma_format(1)) +
	facet_wrap(~cls, scales = 'free_y') +
	theme(axis.ticks = element_blank(),
				legend.position = 'bottom',
				panel.grid.major.x = element_blank(),
				panel.grid.minor.x = element_blank(),
				text = element_text(family = 'serif')) +
	labs(x = 'Optional variables', y = 'Mean RMSE (lower is better)',
			 color = 'Model with the best fit',
			 title = 'Model goodness-of-fit, for each cluster',
			 subtitle = 'ST',
			 caption = str_wrap('The ST diagram represents several thousand potential models, so I intentionally swap the visual metaphor from points to boxplots, although each best-fitting model is still colored orange. Each dataset was tested with cross-validation three times, with each training set consisting of 2/3 of the data. After attempting to predict the testing set\'s values three times, the resulting RMSE metrics were averaged; this is what is illustrated above. NB each y-axis uses a different scale.'))


#### Appendix: export model specifications ####
ForExportAllCoefficients <-
	AllModsFit %>%
		select(prime_mover, cls, pull_size, formula, lm_fit) %>%
		arrange(prime_mover, cls, pull_size, formula) %>%
		mutate(tidy = map(lm_fit, broom::tidy)) %>%
		select(-lm_fit) %>%
		unnest(tidy)
#
ForExportModelGoodnessOfFit <-
	AllModsFit %>%
		select(prime_mover, cls, pull_size, formula, lm_fit) %>%
		arrange(prime_mover, cls, pull_size, formula) %>%
		mutate(glance = map(lm_fit, broom::glance)) %>%
		select(-lm_fit) %>%
		unnest(glance)
#	
write_csv(ForExportAllCoefficients, 'results/all_coefficients.csv')
write_csv(ForExportModelGoodnessOfFit, 'results/model_goodness_of_fit.csv')
	
	
	
	
	
