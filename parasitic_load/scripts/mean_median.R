# Simple model: overall mean and median

library(tidyverse)

Data <- readRDS('clean_data/prepped_data.RDS')

YFit <-
	Data %>%
		select(fold_num, train_prepped) %>%
		mutate(
			gross_generation_mwh = map(train_prepped, 'gross_generation_mwh'),
			mean = map_dbl(gross_generation_mwh, mean),
			median = map_dbl(gross_generation_mwh, median)
		) %>%
		select(fold_num, mean, median) %>%
		gather(model, y_fit, -fold_num) %>%
		mutate(model = str_to_title(model))

YTrue <-
	Data %>%
		mutate(y_true = map(test_prepped, 'gross_generation_mwh')) %>%
		select(fold_num, rowid_test, y_true)

Results <-
	YFit %>%
		left_join(YTrue, by = 'fold_num') %>%
		unnest(c(y_true, rowid_test)) %>%
		relocate(fold_num, model, rowid_test)

write_csv(Results, 'clean_data/results_mean_median.csv')
