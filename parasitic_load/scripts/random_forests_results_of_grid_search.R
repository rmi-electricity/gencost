# final winning specs: 1 estimator, max depth = 250
library(tidyverse)
library(skimr)

# DataBySubplant <- read_csv('clean_data/data_by_subplant.csv')
# DataBySubplant$parasitic_load %>% hist
# DataBySubplant$parasitic_load %>% skim

Rmse <- read_csv('clean_data/random_forest_search_2.csv') %>%
	select(fold_num, num_estimators, max_depth, rmse)

Rmse$rmse %>%
	skim

MeanRmse <-
	Rmse %>%
		group_by(num_estimators, max_depth) %>%
		summarize(mean_rmse = mean(rmse)) %>%
		ungroup

MeanRmse$ecdf <- ecdf(MeanRmse$mean_rmse)(MeanRmse$mean_rmse)

MeanRmse %>%
	mutate(is_ecdf_low = ecdf < 0.02,
				 my_label = if_else(is_ecdf_low, '*', NA_character_)
	) %>%
	ggplot(aes(x = num_estimators, y = max_depth, fill = mean_rmse, label = my_label)) +
	geom_raster() +
	geom_text()

MeanRmse %>%
	arrange(mean_rmse) %>%
	head(5)
