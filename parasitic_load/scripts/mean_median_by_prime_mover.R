# Slightly less simple model: mean and median, by prime_mover

library(tidyverse)
library(Metrics)

NestedDataBySubplant <- readRDS('clean_data/nested_data_by_subplant.RDS')

YFit <-
	NestedDataBySubplant %>%
	select(fold_num, train) %>%
	mutate(
		train = map(train, select, c('prime_mover', 'gross_generation_mwh'))
	) %>%
	unnest(train) %>%
	group_by(fold_num, prime_mover) %>%
	summarize(
		`Mean by prime mover` = mean(gross_generation_mwh),
		`Median by prime mover` = median(gross_generation_mwh)
	) %>%
	ungroup %>%
	gather(model, y_fit, -fold_num, -prime_mover)

GofMeanMedianByPrimeMover <-
	NestedDataBySubplant %>%
		select(fold_num, test) %>%
		mutate(test = map(test, select, c('prime_mover', 'gross_generation_mwh'))) %>%
		unnest(test) %>%
		ungroup %>%
		inner_join(YFit, by = c('fold_num', 'prime_mover')) %>%
		group_by(fold_num, model) %>%
		summarize(rmse = Metrics::rmse(y_fit, gross_generation_mwh)) %>%
		ungroup

write_csv(GofMeanMedianByPrimeMover, 'clean_data/gof_mean_median_by_prime_mover.csv')
