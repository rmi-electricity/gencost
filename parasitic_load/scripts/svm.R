# Support vector machine

library(e1071)
library(skimr)
library(tidyverse)
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

ParamsLinear <-
	tribble(
		~kernel, ~degree, ~cost,
		'linear', NA_integer_, seq(0.5, 1.5, by = .15)
	) %>%
	unnest(everything())

ParamsPolynomial <-
	expand_grid(
		kernel = 'polynomial',
		degree = seq(2L, 4L, by = 1L),
		cost = seq(0.5, 1.5, by = .15)
	)

Params <- bind_rows(ParamsLinear, ParamsPolynomial)

get_svm_fitted_values <- function(
		X_train, y_train, X_test, y_test, kernel, degree, cost){
	# Fit svm regressor and write fitted values to disk, unless
	# values have already been written.

	fn <- str_c(
		'clean_data/svm/kernel_', kernel,
		'_x_degree_', degree,
		'_x_cost', cost,
		'.csv'
	)
	extant_files <- list.files(path = 'clean_data/svm')
	is_already_done	<- str_extract(fn, 'kernel.*$') %in% extant_files
	if(is_already_done){return(NULL)}

	mod_fit <- svm(
		x = X_train,
		y = y_train,
		kernel = kernel,
		degree = degree,
		cost = cost
	)
	y_fit <- predict(object = mod_fit, newdata = X_test)

	Results <-
		y_fit %>%
		enframe(name = NULL, value = 'y_fit') %>%
		mutate(kernel = kernel, degree = degree, cost = cost)
	print(fn)
	write_csv(Results, fn)
}

for (i in seq(1L, nrow(Params))){
	kernel = Params$kernel[[i]]
	degree = Params$degree[[i]]
	cost = Params$cost[[i]]
	get_svm_fitted_values(
			X_train = X_train,
			y_train = y_train,
			X_test = X_test,
			y_test = y_test,
			kernel = kernel,
			degree = degree,
			cost = cost)
}
