library(tidyverse)
library(Metrics)
library(randomForest)

#### Load data for part 1: judging grid search ####
PreppedData <- readRDS('clean_data/prepped_data.RDS')
YTrueNested <-
	PreppedData %>%
		filter(fold_num == 1L) %>%
		mutate(y_true = map(test_prepped, 'gross_generation_mwh')) %>%
		select(y_true)

# 2 searches have been done- large range of parameters, and one to hone in on a small area
# search3 is confirming the performance of the top five models, so don't address that yet
fn_list <- list.files('clean_data/random_forest/', pattern = 'csv', full.names = T, recursive = T)

YFitNested <-
	fn_list %>%
		enframe(name = NULL, value = 'fn') %>%
		filter(!str_detect(fn, 'search3')) %>%
		mutate(
			search_num = str_extract(fn, 'search[0-9]+'),
			search_num = str_extract(search_num, '[0-9]+'),
			search_num = parse_integer(search_num),
			table = map(fn, read_csv, col_types = 'dii')
		)

# Join y_fit and y_true to judge rmse
RMSE <-
	YFitNested %>%
		expand_grid(YTrueNested) %>%
		unnest(c(table, y_true)) %>%
		group_by(search_num, node_size, num_trees) %>%
		summarize(rmse = Metrics::rmse(y_fit, y_true)) %>%
		ungroup

# visualize results
RMSE %>%
	arrange(rmse) %>%
	rowid_to_column('rank') %>%
	mutate(rank = if_else(rank <= 5L, rank, NA_integer_),
				 num_trees = num_trees) %>%
	ggplot(aes(x = node_size, y = num_trees, fill = rmse, label = rank)) +
	geom_raster() +
	geom_text(color = 'red') +
	facet_wrap(~search_num, scales = 'free') +
	theme(panel.background = element_blank())

# Look at top five RMSE scores (noting that this is just for fold n1)
TopFiveParameters <-
	RMSE %>%
		arrange(rmse) %>%
		head(5) %>%
		rowid_to_column('rank') %>%
		select(rank, node_size, num_trees)

TopFiveParameters

#### Part 2: fit top five mods on all folds ####
ModelMe <-
	PreppedData %>%
		expand_grid(TopFiveParameters) %>%
		mutate(
			y_train = map(train_prepped, 'gross_generation_mwh'),
			X_train = map(train_prepped, ~select(., -gross_generation_mwh)),
			X_train = map(X_train, as.matrix),

			y_test = map(test_prepped, 'gross_generation_mwh'),
			X_test = map(test_prepped, ~select(., -gross_generation_mwh)),
			X_test = map(X_test, as.matrix),
		) %>%
		select(rank, node_size, num_trees, fold_num, X_train, y_train, X_test, y_test)

# for (i in seq(1, nrow(ModelMe))){
# 	directory <- 'clean_data/random_forest/search3_comparison_of_best_five/'
# 	fn <- str_c(
# 		'node_size_', ModelMe$node_size[[i]],
# 		'_x_num_trees_', ModelMe$num_trees[[i]],
# 		'_x_fold_num_', ModelMe$fold_num[[i]],
# 		'.csv'
# 	)
# 	dir_fn <- str_c(directory, fn)
# 	print(i)
# 	print(fn)
#
# 	mod_fit <- randomForest(
# 		x = ModelMe$X_train[[i]],
# 		y = ModelMe$y_train[[i]],
# 		nodesize = ModelMe$node_size[[i]],
# 		ntree = ModelMe$num_trees[[i]]
# 	)
# 	y_fit <- enframe(predict(mod_fit, ModelMe$X_test[[i]]))
# 	write_csv(y_fit, dir_fn)
# }

# load results
fn_list2 <- list.files(path = 'clean_data/random_forest/search3_comparison_of_best_five/', full.names = T)

YFitNested2 <-
	fn_list2 %>%
		enframe(name = NULL, value = 'fn') %>%
		mutate(
			data = map(fn, read_csv, col_types = 'id'),
			fn_no_dir = str_replace(fn, 'clean_data/random_forest/search3_comparison_of_best_five//', '')
		) %>%
		separate(fn_no_dir, c('node_size', 'num_trees', 'fold_num'), sep = '_x_') %>%
		mutate_at(c('node_size', 'num_trees', 'fold_num'), str_extract, '[0-9]+') %>%
		mutate_at(c('node_size', 'num_trees', 'fold_num'), parse_integer) %>%
		select(-fn)

RMSE2 <-
	ModelMe %>%
		select(rank, node_size, num_trees, fold_num, y_test) %>%
		left_join(YFitNested2, by = c('node_size', 'num_trees', 'fold_num')) %>%
		mutate(y_fit = map(data, 'value')) %>%
		select(-data) %>%
		unnest(c(y_test, y_fit)) %>%
		group_by(rank, node_size, num_trees, fold_num) %>%
		summarize(rmse = Metrics::rmse(y_test, y_fit)) %>%
		ungroup

# depending on if we use mean or median, node_size = 1 and num_trees is
# either 240 or 183. use 183 for simplicity's sake.
RMSE2 %>%
	group_by(node_size, num_trees) %>%
	summarize(mean_rmse = mean(rmse), median_rmse = median(rmse)) %>%
	ungroup %>%
	arrange(mean_rmse)

ModelMe %>%
	select(rank, node_size, num_trees, fold_num, y_test) %>%
	left_join(YFitNested2, by = c('node_size', 'num_trees', 'fold_num')) %>%
	mutate(
		y_fit = map(data, 'value'),
		model = 'Random Forest'
	) %>%
	filter(node_size == 1L, num_trees == 183L) %>%
	rename(y_true = y_test) %>%
	select(model, fold_num, y_true, y_fit) %>%
	unnest(c(y_true, y_fit)) %>%
	write_csv('clean_data/results_random_forest.csv')
