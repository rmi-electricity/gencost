# Simple model: overall mean and median

library(tidyverse)
library(Metrics)
# library(skimr)

set.seed(1)
# DataBySubplant <- read_csv('clean_data/clean_data_by_subplant.csv')
NestedDataBySubplant <- readRDS('clean_data/nested_data_by_subplant.RDS')

YFit <-
	NestedDataBySubplant %>%
		select(fold_num, train) %>%
		mutate(
			train = map(train, 'gross_generation_mwh'),
			mean = map_dbl(train, mean),
			median = map_dbl(train, median),
		) %>%
		select(fold_num, mean, median)

GofMeanMedian <-
	NestedDataBySubplant %>%
		inner_join(YFit, by = 'fold_num') %>%
		mutate(y = map(test, 'gross_generation_mwh')) %>%
		select(fold_num, mean, median, y) %>%
		gather(model, y_fit, -fold_num, -y) %>%
		unnest(y) %>%
		group_by(fold_num, model) %>%
		summarize(rmse = Metrics::rmse(y, y_fit)) %>%
		ungroup %>%
		mutate(model = str_to_title(model))

write_csv(GofMeanMedian, 'clean_data/gof_mean_median.csv')
