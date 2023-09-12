# Support vector machine

library(e1071)
library(skimr)
library(tidyverse)
# library(Metrics)
set.seed(1)

#### Load data ####
setwd(dir = '~/Documents/rmi/gencost/parasitic_load/')
PreppedData <- readRDS('clean_data/prepped_data.RDS')

cost_list <- c(100, 112, 114, 166)
ModelMe <-
	PreppedData %>%
		mutate(
			X_train = map(train_prepped, select, -parasitic_load),
			X_train = map(X_train, as.matrix),
			y_train = map(train_prepped, 'parasitic_load'),

			X_test = map(test_prepped, select, -parasitic_load),
			X_test = map(X_test, as.matrix),
			y_test = map(test_prepped, 'parasitic_load')
		) %>%
		select(fold_num, X_train, y_train, X_test, y_test) %>%
		expand_grid(cost = cost_list) %>%
		mutate(
			fn = str_c('kernel_linear',
								 '_x_cost_', cost,
								 '_x_fold_num_', fold_num,
								 '.csv')
		)

# fit models
setwd('clean_data/svm/')
n_row = nrow(ModelMe)
for (i in seq(1, n_row)){
	X_train <- ModelMe$X_train[[i]]
	y_train <- ModelMe$y_train[[i]]
	X_test <- ModelMe$X_test[[i]]
	y_test <- ModelMe$y_test[[i]]
	c <- ModelMe$cost[[i]]
	fn <- ModelMe$fn[[i]]

	mod_fit <- svm(
		x = X_train,
		y = y_train,
		kernel = 'linear',
		cost =c
	)
	y_fit <- predict(object = mod_fit, newdata = X_test)

	Results <-
		y_fit %>%
		enframe(name = NULL, value = 'y_fit') %>%
		mutate(
			kernel = 'linear',
			cost = c
		)
	Results$y_true <- y_test
	print(fn)
	write_csv(Results, fn)
}
