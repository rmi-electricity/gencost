# lm

library(tidyverse)
library(skimr)
set.seed(1)

PreppedData <- readRDS('clean_data/prepped_data.RDS')

YFit <-
	PreppedData %>%
		mutate(
			lm_fit = map(train_prepped, lm,
				formula = 'gross_generation_mwh ~ net_generation_mwh + capacity_mw + age_of_observation + age_in_report_year'
			),
			y_fit = map2(lm_fit, test_prepped, predict.lm),
			y_true = map(test_prepped, 'gross_generation_mwh'),
		)

Results <-
	YFit %>%
		mutate(model = 'Linear regression') %>%
		select(fold_num, model, rowid_test, y_fit, y_true) %>%
		unnest(c(rowid_test, y_fit, y_true))

write_csv(Results, 'clean_data/results_lm.csv')
