# Random Forests

library(tidyverse)
library(skimr)
library(randomForest)
# library(Metrics)
set.seed(1)

#### Load data ####
PreppedData <- readRDS('clean_data/prepped_data.RDS') %>%
	filter(fold_num == 1L)


Train <- PreppedData$train_prepped[[1]]
Test <- PreppedData$test_prepped[[1]]

X_train <- Train %>%
	select(-gross_generation_mwh) %>%
	as.matrix
y_train <- Train$gross_generation_mwh

X_test <- Test %>%
	select(-gross_generation_mwh) %>%
	as.matrix
y_test <- Test$gross_generation_mwh



get_random_forest_fitted_values <- function(
		X_train, y_train, X_test, y_test, node_size, num_trees){
	# Fit random forest regressor and write fitted values to disk, unless
	# values have already been written.

	fn <- str_c(
		'clean_data/random_forest/node_size_', node_size,
		'_x_num_trees_', num_trees, '.csv'
	)
	extant_files <- list.files(path = 'clean_data/random_forest')
	is_already_done	<- str_extract(fn, 'node_size.*$') %in% extant_files
	if(is_already_done){return(NULL)}


	mod_fit <- randomForest(
		x = X_train,
		y = y_train,
		ntree = num_trees,
		nodesize = node_size)

	y_fit <- predict(object = mod_fit, newdata = X_test)

	Results <-
		y_fit %>%
			enframe(name = NULL, value = 'y_fit') %>%
			mutate(node_size = node_size, num_trees = num_trees)

	print(fn)
	write_csv(Results, fn)
}

for (n in seq(1, 5, by = 1)){
	for (t in seq(1, 250, by = 1)){
		get_random_forest_fitted_values(
			X_train = X_train,  y_train = y_train, X_test = X_test, y_test = y_test,
			node_size = n, num_trees = t
		)
	}
}
