# Feature Engineering
# Parasitic Load project
# Andrew Bartnof
# abartnof.contractor@rmi.org
# 2023, for RMI

library(tidyverse)
library(skimr)
library(recipes)
library(modelr)
library(conflicted)
conflicted::conflict_prefer('map', 'purrr')
# library(rsample)
set.seed(1)

#### Load data ####
DataBySubplant <- read_csv('clean_data/data_by_subplant.csv')

# Recipes
SplitData <-
	DataBySubplant %>%
		# select(-rowid) %>%
		crossv_kfold(k = 5L, id = 'fold_num') %>%
		mutate(
			fold_num = parse_integer(fold_num),
			train = map(train, as.data.frame),
			test = map(test, as.data.frame),
			rowid_test = map(test, 'rowid'),
			rowid_train = map(train, 'rowid'),
			train = map(train, select, -rowid),
			test = map(test, select, -rowid),
			) %>%
		relocate(fold_num)

recipe_object <- recipe(gross_generation_mwh ~ .,
												data = select(DataBySubplant, -rowid))
# recipe_object

imputed <- recipe_object %>%
	step_impute_median(all_numeric_predictors()) %>%
	step_impute_mode(all_nominal_predictors())
# imputed

dummy_coding <- imputed %>%
	step_dummy(all_nominal_predictors())
# dummy_coding

standardized <- dummy_coding %>%
	step_center(all_numeric_predictors()) %>%
	step_scale(all_numeric_predictors())
# standardized

# Apply the data manipulations to the data which has been split into
# training/test sets
PreppedData <-
	SplitData %>%
		mutate(
			train_prepped = map(train,
				~bake(prep(x = standardized, training = .), new_data = .)
			),
			test_prepped = map2(train, test,
				~bake(prep(x = standardized, training = .x), new_data = .y)
			)
		)

PreppedData %>%
	# save item, omitting non-prepped objects, to avoid any confusion
	select(fold_num, train_prepped, test_prepped, rowid_train, rowid_test) %>%
	saveRDS('clean_data/prepped_data.RDS')

PreppedData %>%
	# save everything
	saveRDS('clean_data/original_data_nested.RDS')
