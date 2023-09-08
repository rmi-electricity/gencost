# Support vector machine

library(e1071)
library(skimr)
library(tidyverse)
# library(Metrics)
set.seed(1)

#### Load data ####
setwd(dir = '~/Documents/rmi/gencost/parasitic_load/')
PreppedData <- readRDS('clean_data/prepped_data.RDS') %>%
	filter(fold_num == 1L)

Train <- PreppedData$train_prepped[[1]]
Test <- PreppedData$test_prepped[[1]]

X_train <- Train %>%
	select(-parasitic_load) %>%
	as.matrix
y_train <- Train$parasitic_load

X_test <- Test %>%
	select(-parasitic_load) %>%
	as.matrix
y_test <- Test$parasitic_load

Params <-
	tribble(
		~kernel, ~cost,
		'linear', seq(105, 114)
	) %>%
	unnest(everything()) %>%
	mutate(
		fn = str_c('kernel_', kernel,
							 '_x_',
							 'cost_', cost,
							 '.csv'
							 )
	)
Params

# # ParamsPolynomial <-
# 	expand_grid(
# 		kernel = 'polynomial',
# 		degree = seq(2L, 5L, by = 1L),
# 		cost = 10**(seq(-3, 3))
# 	)

setwd('clean_data/svm/')

get_svm_fitted_values <- function(
		X_train, y_train, X_test, y_test, kernel, cost, fn){
	# Fit svm regressor and write fitted values to disk, unless
	# values have already been written.

	# fn <- str_c(
	# 	'kernel_', kernel,
	# 	'_x_degree_', degree,
	# 	'_x_cost', cost,
	# 	'.csv'
	# )
	# extant_files <- list.files(path = '')
	# is_already_done	<- str_extract(fn, 'kernel.*$') %in% extant_files
	# if(is_already_done){return(NULL)}

	mod_fit <- svm(
		x = X_train,
		y = y_train,
		kernel = kernel,
		# degree = degree,
		cost = cost
	)
	y_fit <- predict(object = mod_fit, newdata = X_test)

	Results <-
		y_fit %>%
		enframe(name = NULL, value = 'y_fit') %>%
		mutate(
			kernel = kernel,
			cost = cost
		)
	print(fn)
	write_csv(Results, fn)
}

for (i in seq(1L, nrow(Params))){
	kernel = Params$kernel[[i]]
	# degree = Params$degree[[i]]
	cost = Params$cost[[i]]
	fn = Params$fn[[i]]
	get_svm_fitted_values(
			X_train = X_train,
			y_train = y_train,
			X_test = X_test,
			y_test = y_test,
			kernel = kernel,
			# degree = degree,
			cost = cost,
			fn = fn)
}
