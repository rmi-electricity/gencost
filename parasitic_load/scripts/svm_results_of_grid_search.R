library(tidyverse)
library(skimr)
library(Metrics)
library(e1071)

#### Load data for part 1: judging grid search ####
PreppedData <- readRDS('clean_data/prepped_data.RDS')
YTrueNested <-
	PreppedData %>%
	filter(fold_num == 1L) %>%
	mutate(y_true = map(test_prepped, 'gross_generation_mwh')) %>%
	select(y_true)

fn_list <- list.files('clean_data/svm/search1/', full.names = T)

NestedYFit <-
	fn_list %>%
		enframe(name = NULL, value = 'fn') %>%
		mutate(data = map(fn, read_csv))

NestedYFit %>%
	unnest(data)

RMSE <-
	NestedYFit %>%
		expand_grid(YTrueNested) %>%
		unnest(c(data, y_true)) %>%
		group_by(kernel, degree, cost) %>%
		summarize(rmse = Metrics::rmse(y_fit, y_true)) %>%
		ungroup

RMSE %>%
	ggplot(aes(x = ordered(degree), y = cost, fill = rmse)) +
	geom_raster() +
	facet_wrap(~kernel, scales = 'free')

RmseTop3 <-
	RMSE %>%
		arrange(rmse) %>%
		head(3)

# Fit top 3 models to conclusively test fit
RmseTop3

for (i in seq(1L, 5L)){  # row in Prepped data (1 row per fold)
	for (c in seq(1, 3, by = .1)){ # cost
		cost <- c
		fold_num <- PreppedData$fold_num[[i]]
		Train <- PreppedData$train_prepped[[i]]
		Test <- PreppedData$test_prepped[[i]]

		y_train <- Train$gross_generation_mwh
		X_train <- Train %>% select(-gross_generation_mwh) %>% as.matrix
		X_test <- Test %>% select(-gross_generation_mwh) %>% as.matrix

		fn <- str_c('fold_num_', fold_num,
								'_x_cost_', cost,
								'_x_kernel_polynomial_x_degree_3.csv')
		print(c(i, c, fn))

		svm_fit <- svm(
			x = X_train,
			y = y_train,
			formula = gross_generation_mwh ~ .,
			cost = cost,
			kernel = 'polynomial',
			degree = 3L)
		y_fit <- predict(svm_fit, X_test)
		y_fit %>%
			enframe(name = NULL, value = 'y_fit') %>%
			mutate(kernel = 'polynomial', degree = 3, cost = cost) %>%
			write_csv(fn)
	}
}
