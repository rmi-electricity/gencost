# GenCost workflow
# 4. Regressions
# Andrew Bartnof, for RMI, 2023

# We'll want linear regression models, one per cluster, to predict real_opex.
# We know which variables are necessary, and which should not be used; 
# for each prime_mover, for each cluster, iterate through all 
# possible models that contain all necessary variables, and may contain 
# any number of optional variables, to find the formula with the best
# fit. Note that we'll use training and testing sets to ensure we don't
# overfit on the data.
# This script is a bit computationally-expensive, because of how many
# models it compares.


#### Import libraries ####
library(tidyverse)
library(skimr)
library(broom)
library(conflicted)
library(gtools)
# library(leaps)
# library(Metrics)
conflicted::conflict_prefer('map', 'purrr')
conflicted::conflict_prefer('map2', 'purrr')
conflicted::conflict_prefer('filter', 'dplyr')
set.seed(1)	


#### Load data ####

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
		mutate(core_variables = map(data, pull)) %>%
		select(prime_mover, core_variables)

# Likewise, put optional variables in a list, per prime_mover
OptionalVariables <-
	LongVariableKey %>%
		filter(variable_type == 'optional') %>%
		select(prime_mover, variable) %>%
		nest(data = variable) %>%
		rename(optional_variables = data) %>%
		mutate(optional_variables = map(optional_variables, pull))
OptionalVariables

JoinmeSequence <-
	# A table that ranges from 1:the number of possible add'l variables
	OptionalVariables %>%
		mutate(
			low = 1, 
			high = map_int(optional_variables, length),
			sequence = map2(low, high, seq)
			) %>%
		select(prime_mover, sequence)
JoinmeSequence

RowsWhichSignifyNoOptionalVariables <-
	# Since we'll make formulas be concatenating the core bits with the 
	# optional bits, we'll need to make a placeholder with no optional bits
	# that can be 'concatenated' with the core bits-- ie no optional bits, just core
	tribble(
		~prime_mover, ~pull_size, ~optional_variables,
		c('CC', 'GT', 'ST'), 0L, '' 
	) %>%
	unnest(prime_mover)
RowsWhichSignifyNoOptionalVariables

ComponentsOfFormulasOptional <-
	# The optional halves of formulas that will be appended to the core halves
	OptionalVariables %>%
		left_join(JoinmeSequence) %>%
		unnest(sequence) %>%
		rename(pull_size = sequence) %>%
		mutate(
			combination = map2(optional_variables, pull_size, 
												 ~combn(x = .x, m = .y, FUN = paste, collapse = ' + ',
												 			 simplify = FALSE)),
			combination = map(combination, unlist)
			) %>%
		select(prime_mover, pull_size, combination) %>%
		unnest(combination) %>%
		rename(optional_variables = combination) %>%
		mutate(optional_variables = str_c(' + ', optional_variables)) %>%
		bind_rows(RowsWhichSignifyNoOptionalVariables) %>% # add above-created placeholders
		arrange(prime_mover, pull_size, optional_variables)
ComponentsOfFormulasOptional

ComponentsOfFormulasCoreAndDv <-
	# the core parts of the formulas, as well as the DV
	CoreVariables %>%
		mutate(
			core_variables = map_chr(core_variables, paste0, collapse = ' + '),
			core_variables_and_dv = str_c('real_opex ~ 0 + ', core_variables)
		) %>%
		select(prime_mover, core_variables_and_dv)
ComponentsOfFormulasCoreAndDv

AllFormulas <-
	ComponentsOfFormulasCoreAndDv %>%
		inner_join(ComponentsOfFormulasOptional, by = 'prime_mover') %>%
		unite('formula', c('core_variables_and_dv', 'optional_variables'), sep = '')

AllFormulas %>%
	count(prime_mover)


#### Train and Test the models ####
# create training and testing datasets: 3 folds per cluster
# Pls note that the following few steps are computationally expensive, and if they have 
# been run before, you can simply load the RMSE results that are saved
# to disk a few lines down, and continue from there!
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
TrainTest

# Fan out by joining each train/test row to all of the prime mover's formulas
# Get fitted values and note RMSE
# Note: this is computationally expensive
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
		group_by(prime_mover, cls, formula, boot_num) %>%  # removed: pull_size
		summarize(rmse = sqrt(mean(residual^2))) %>%
		ungroup

####
write_csv(RMSE, 'clean_data/all_models_rmse.csv')


#### Start here if you simply want to read extant RMSE data ####
RMSE <- read_csv('clean_data/all_models_rmse.csv', 
								 col_types = c(prime_mover = 'c', formula = 'c', cls = 'i', 
								 							boot_num = 'i', rmse = 'd'))

# Aggregate the RMSE over each of the CV folds, so that we have a mean
# RMSE value per formula, per prime_mover, per cluster
MeanRMSE <-
	RMSE %>%
		group_by(prime_mover, cls, formula) %>%
		summarize(mean_rmse = mean(rmse)) %>%
		ungroup

# We'll want to find the formula, per cluster, with the lowest MeanRMSE:
# but first, use the models fit on all the data to exclude any model that
# has too much colinearity, and gives us missing values for any coefficient
# This means that ultimately, we'll find the lowest RMSE per cluster from the MeanRMSE table ASSUMING the formula doesn't break due to colinearity
# when it's fit to the entire dataset:

AllModsFit <-
	# Fit now using the whole dataset in clusters, NOT train/test
	ClustersFit %>%
		select(prime_mover, rowid, cls) %>%
		unnest(c(rowid, cls)) %>%
		inner_join(CleanedDataBySubplant, by = c('prime_mover', 'rowid')) %>%
		group_by(prime_mover, cls) %>%
		nest %>%
		ungroup %>%
		arrange(prime_mover, cls) %>%
		left_join(AllFormulas, by = c('prime_mover')) %>%
		mutate(
			lm_fit = map2(formula, data, lm),
			# coefficients = map(lm_fit, coefficients),
			# coefficients = map(coefficients, enframe, name = 'variable', value = 'coefficient'),
		)

# Exclude models with missing coefficients due to colinearity
FunctionalModelCheck <-
	AllModsFit %>%
		mutate(
			coefficients = map(lm_fit, coefficients),
			coefficients = map(coefficients, enframe, name = 'variable', value = 'coefficient'),
		) %>%
		select(prime_mover, cls, formula, coefficients) %>%
		unnest(coefficients) %>%
		group_by(prime_mover, cls, formula) %>%
		summarize(is_functional_model = sum(is.na(coefficient)) == 0L) %>%
		ungroup

#
ChosenFormulas <-
	# Chosen model has the smallest mean rmse- ties are broken by which
	# model adds the fewest extra variables (pull size)
	MeanRMSE %>%
		inner_join(FunctionalModelCheck, by = c('prime_mover', 'cls', 'formula')) %>%
		left_join(AllFormulas, by = c('prime_mover', 'formula')) %>%
		filter(is_functional_model) %>%
		group_by(prime_mover, cls) %>%
		arrange(mean_rmse, pull_size) %>%
		rowid_to_column('rank') %>%
		slice(which.min(rank)) %>%
		ungroup %>%
		select(prime_mover, cls, formula)

print(ChosenFormulas)

# sanity check- is there a functional model for each cluster?
X <-
	ChosenFormulas %>%
		distinct(prime_mover, cls) %>%
		arrange(prime_mover, cls)

Y <-
	ClustersFit %>%
		unnest(cls) %>%
		distinct(prime_mover, cls) %>%
		arrange(prime_mover, cls)
identical(X, Y)

# Dataviz to show the models we chose
# x axis is add'l variables, y is rmse, colors indicate functional and is_chosen
Results <-
	AllFormulas %>%
		full_join(MeanRMSE, by = c('prime_mover', 'formula')) %>%
		full_join(FunctionalModelCheck) %>%
		left_join(
			ChosenFormulas %>% mutate(is_chosen = TRUE)
		) %>%
		mutate(
			is_chosen = replace_na(is_chosen, FALSE),
			my_color = case_when(
				is_chosen ~ 'Chosen',
				is_functional_model ~ 'Valid model, not chosen',
				!is_functional_model ~ 'Non-valid model',
				TRUE ~ 'DEFAULT UNKNOWN'
			),
			my_color = ordered(my_color, c('Chosen', 'Valid model, not chosen', 'Non-valid model')),
			# my_color = fct_rev(my_color)
		)
Results

Results %>%
	filter(prime_mover == 'ST') %>%
	ggplot(aes(x = pull_size, y = mean_rmse)) +
	geom_smooth(method = 'lm', formula = 'y ~ poly(x, 3)') +
	# expand_limits(y = 0) +
	scale_x_continuous(breaks = seq(0, 10)) +
	scale_y_continuous(labels = scales::comma_format(1)) +
	facet_wrap(~cls, scales = 'free') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.minor.x = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = 'Number of optional variables', 
			 y = 'Mean RMSE',
			 title = 'Mean RMSE across training/test sets: ST',
			 caption = 'Note that these are zoomed in, and the y-axes do not include zero')
#	

# sanity check on number of clusters * formulas to make sure we fit the right #
NumClusters <-
	ClustersFit %>%
		select(prime_mover, num_clusters)
NumFormulas <-
	AllFormulas %>%
		count(prime_mover) %>%
		inner_join(NumClusters, by = 'prime_mover') %>%
		mutate(subtotal = n * num_clusters)
sum(NumFormulas$subtotal)

ChosenModsFit <-
	AllModsFit %>%
		inner_join(ChosenFormulas)

ChosenCoefficients <-
	ChosenModsFit %>%
		mutate(
			coefficients = map(lm_fit, coefficients),
			coefficients = map(coefficients, enframe, name = 'variable', value = 'coefficient')
		) %>%
		select(prime_mover, cls, formula, coefficients) %>%
		unnest(coefficients) %>%
		left_join(LongVariableKey, by = c('prime_mover', 'variable'))

# Ensure each category of variable is accounted for
ChosenCoefficients %>%
	mutate_at(c('prime_mover', 'category'), factor) %>%
	count(prime_mover, cls, category, .drop = F) %>%
	spread(category, n)

write_csv(ChosenCoefficients, 'clean_data/chosen_coefficients.csv')
write_csv(ChosenFormulas, 'clean_data/chosen_formulas.csv')
write_csv(MeanRMSE, 'clean_data/mean_rmse.csv')

#### End Here^. Appendix: reporting goodness of fit ####
# color scheme: water and rust
# https://color.adobe.com/explore

AllFormulas %>%
	count(prime_mover)

MeanRMSE %>%
	count(prime_mover, cls)

JoinmeIsChosen <-
	ChosenFormulas %>%
		mutate(is_chosen = TRUE)

MeanRMSE %>%
	left_join(JoinmeIsChosen) %>%
	mutate(is_chosen = replace_na(is_chosen, FALSE)) %>%
	


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
JoinmeIsChosen <-
	ChosenFormulas %>%
		select(prime_mover, cls, pull_size, formula) %>%
		mutate(is_chosen = TRUE)

AllModsFit %>%
	head %>%
	select(prime_mover, cls, pull_size, formula, lm_fit) %>%
	arrange(prime_mover, cls, pull_size, formula) %>%
	mutate(
		summary = map(lm_fit, summary),
		summary = map(summary, tidy)
	) %>%
	select(-lm_fit) %>%
	unnest(summary)
	print


ForExportAnova <-	
	AllModsFit %>%
		select(prime_mover, cls, pull_size, formula, lm_fit) %>%
		left_join(JoinmeIsChosen) %>%
		mutate(is_chosen = replace_na(is_chosen, FALSE)) %>%
		arrange(prime_mover, cls, pull_size, formula) %>%
		mutate(
			anova = map(lm_fit, anova),
			anova = map(anova, as.data.frame),
			anova = map(anova, rownames_to_column, 'variable')) %>%
		select(-lm_fit) %>%
		unnest(anova)
ForExportAnova
write_csv(ForExportAnova, 'results/anova.csv')
