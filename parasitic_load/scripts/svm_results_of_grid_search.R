library(tidyverse)
library(skimr)
library(Metrics)
library(e1071)

#### Load data for part 1: judging grid search ####
PreppedData <- readRDS('clean_data/prepped_data.RDS')
YTrueNested <-
	PreppedData %>%
	filter(fold_num == 1L) %>%
	mutate(y_true = map(test_prepped, 'parasitic_load')) %>%
	select(y_true)

fn_list <- list.files('clean_data/svm/', full.names = T, recursive = T, pattern = '*.csv')
fn_list

NestedYFit <-
	fn_list %>%
		enframe(name = NULL, value = 'fn') %>%
		mutate(
			search = str_extract(fn, 'svm linear [0-9]+'),
			search = str_extract(search, '[0-9]+'),
			search = parse_integer(search),
			data = map(fn, read_csv)
		)

RMSE <-
	NestedYFit %>%
		expand_grid(YTrueNested) %>%
		unnest(c(data, y_true)) %>%
		group_by(search, kernel, cost) %>%
		summarize(rmse = Metrics::rmse(y_fit, y_true)) %>%
		ungroup

RMSE %>%
	filter(cost > 90, cost < 150) %>%
	arrange(cost)

RMSE %>%
	mutate(cost = round(cost)) %>%
	ggplot(aes(x = cost, y = rmse)) +
	coord_cartesian(xlim = c(0, 250)) +
	# geom_smooth() +
	geom_point(aes(color = ordered(search)))
	# facet_wrap(~search, scales = 'free_x')


RMSE %>%
	ggplot(aes(x = degree, y = cost, fill = rmse)) +
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

# judge this recent search

NestedYFitFinal <-
	list.files(path = 'clean_data/svm/search2', full.names = T) %>%
		enframe(name = NULL, value = 'fn') %>%
		mutate(data = map(fn, read_csv))

JoinmeYFitFinal <-
	NestedYFitFinal	%>%
		mutate(
			fold_num = str_extract(fn, 'fold_num_[0-9]+'),
			fold_num = str_extract(fold_num, '[0-9]+'),
			fold_num = parse_integer(fold_num)
		)

JoinmeYTrue <-
	PreppedData %>%
		mutate(
			y_true = map(test_prepped, 'gross_generation_mwh')
		) %>%
		select(fold_num, rowid_test, y_true)

RmseFinal <-
	JoinmeYFitFinal	%>%
		left_join(JoinmeYTrue, by = c('fold_num')) %>%
		unnest(c(data, y_true)) %>%
		group_by(fold_num, kernel, degree, cost) %>%
		summarize(rmse = Metrics::rmse(y_true, y_fit)) %>%
		ungroup

RmseFinal %>%
	ggplot(aes(x = ordered(cost), y = rmse)) +
	geom_boxplot()

RmseFinal %>%
	group_by(kernel, degree, cost) %>%
	summarize(mean_rmse = mean(rmse)) %>%
	ungroup %>%
	arrange(mean_rmse)

# use this:
# kernel: polynomial
# degree: 3
# cost: 1.4
# mean rmse: 381072.


JoinmeYFitFinal	%>%
	left_join(JoinmeYTrue, by = c('fold_num')) %>%
	unnest(c(fold_num, rowid_test, data, y_true)) %>%
	filter(kernel == 'polynomial', degree == 3, cost == 1.4) %>%
	mutate(model = 'Support vector machine') %>%
	select(fold_num, model, rowid_test, y_fit, y_true) %>%
	write_csv('clean_data/results_svm')
