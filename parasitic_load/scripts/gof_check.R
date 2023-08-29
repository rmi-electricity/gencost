library(tidyverse)
library(skimr)
library(Metrics)

PreppedData <- readRDS('clean_data/prepped_data.RDS')
OriginalDataNested <- readRDS('clean_data/original_data_nested.RDS')

# rules to apply to fitted values:
# gross_generation_mwh distribution should be approx same as training           gross_generation_mwh (worst test)

fn_list <- list.files(path = 'clean_data/', pattern = 'results*', full.names = T, recursive = F)
Results <-
	enframe(fn_list, name = NULL, value = 'fn') %>%
		mutate(data = map(fn, read_csv)) %>%
		unnest(data) %>%
		select(fold_num, model, y_fit, y_true)
# Results <- read_csv('clean_data/results_mean_median.csv')

# Compare RMSE
Results %>%
	group_by(model, fold_num) %>%
	summarize(rmse = Metrics::rmse(y_true, y_fit)) %>%
	ungroup %>%
	mutate(model = fct_reorder(model, rmse, median)) %>%
	ggplot(aes(x = model, y = rmse)) +
	geom_boxplot() +
	coord_flip() +
	expand_limits(y = 0)

# Check: gross_generation_mwh cannot be <0 (MOST IMPORTANT CHECK)
MinYFit <-
	Results %>%
		group_by(model) %>%
		summarize(min_y_fit = min(y_fit)) %>%
		ungroup
print(MinYFit)

min_check <- all(MinYFit$min_y_fit >= 0)
str_c('Check 1: gross_generation_mwh cannot be negative: ', min_check)

# Check: gross_generation_mwh should be at or higher than net generation_mwh
# (ie parasitic load should be zero or positive)

NetGenerationMwh <-
	OriginalDataNested %>%
		mutate(net_generation_mwh = map(test, 'net_generation_mwh')) %>%
		select(fold_num, rowid_test, net_generation_mwh) %>%
		unnest(c(rowid_test, net_generation_mwh))

PropYFitGreaterThanNetGenerationMwh <-
	NetGenerationMwh %>%
		left_join(Results, by = c('fold_num', 'rowid_test')) %>%
		mutate(is_y_fit_greater_than_net_generation_mwh = y_fit >= net_generation_mwh) %>%
		group_by(model) %>%
		summarize(prop_y_fit_greater_than_net_generation_mwh = mean(is_y_fit_greater_than_net_generation_mwh)) %>%
		ungroup

print(PropYFitGreaterThanNetGenerationMwh)


# gross_generation_mwh distribution should look like net_generation_mwh, but shifted to the right a bit (diff is parasitic_load)
NetAndGrossLong <-
	NetGenerationMwh %>%
		left_join(Results, by = c('fold_num', 'rowid_test')) %>%
		rename(`True Gross Generation MWh` = y_true,
					 `Fitted Gross Generation MWh` = y_fit,
					 `Net Generation MWh` = net_generation_mwh) %>%
		gather(metric, value, -fold_num, -rowid_test, -model) %>%
		mutate(metric = ordered(metric,
														c('Net Generation MWh', 'True Gross Generation MWh', 'Fitted Gross Generation MWh')))

NetAndGrossLong	%>%
	ggplot(aes(x = value)) +
	geom_density(aes(group = metric, color = metric)) +
	facet_wrap(~model, scales = 'free')
