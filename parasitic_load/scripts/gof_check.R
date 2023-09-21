library(tidyverse)
library(skimr)
library(Metrics)

# PreppedData <- readRDS('clean_data/prepped_data.RDS')
OriginalDataNested <- readRDS('clean_data/original_data_nested.RDS')

PyOriginalData <-
	list.files(path = 'clean_data_py/test/', pattern = 'csv', full.names = T) %>%
		enframe(name = NULL, value = 'fn') %>%
		arrange(fn) %>%
		mutate(
			fold_num = str_extract(fn, '[0-9]+'),
			data = map(fn, read_csv)
		) %>%
		unnest(data) %>%
		select(-fn)

#### Load data ####
MeanMedian <- read_csv('results/mean_median.csv')
MeanMedian
	select(model, fold_num, y_fit, y_true)

SvmLinear <-
	list.files(path = 'results/svm linear/', full.names = T) %>%
		enframe(name = NULL, value = 'fn') %>%
		mutate(data = map(fn, read_csv)) %>%
		unnest(data) %>%
		mutate(
			model = 'SVM (Linear)',
			fold_num = str_extract(fn, 'fold_num_[0-9]+'),
			fold_num = str_extract(fold_num, '[0-9]+'),
			fold_num = parse_integer(fold_num)
			) %>%
		select(model, fold_num, y_fit, y_true)

SvmPolynomial <-
	list.files(path = 'results/svm poly/', full.names = T) %>%
		enframe(name = NULL, value = 'fn') %>%
		arrange(fn) %>%
		mutate(data = map(fn, read_csv)) %>%
		unnest(data) %>%
		mutate(model = 'SVM (Polynomial)') %>%
		select(model, fold_num, y_fit, y_true)

SvmPolynomial
PyOriginalData %>%
	select(net_generation_mwh, gross_)
table(near(PyOriginalData$parasitic_load, SvmPolynomial$y_true))
# Insert random forests here

AllMods <-
	MeanMedian %>%
		bind_rows(SvmLinear) %>%
		bind_rows(SvmPolynomial)


# ensure there's the same number of rows per model
AllMods %>%
	count(model) %>%
	mutate(is_correct_amt = n == nrow(DataBySubplant)) # ELT was slightly different in python


#### RMSE ####
Rmse <-
	AllMods %>%
		group_by(model, fold_num) %>%
		summarize(rmse = Metrics::rmse(y_fit, y_true)) %>%
		ungroup

Rmse %>%
	ggplot(aes(x = model, y = rmse)) +
	geom_point()

Rmse %>%
	group_by(model) %>%
	summarize(
		mean_rmse = mean(rmse),
		low = mean_rmse - sd(rmse),
		high = mean_rmse + sd(rmse),
		) %>%
	ungroup %>%
	ggplot(aes(x = model, y = mean_rmse)) +
	geom_point() +
	geom_linerange(aes(ymin = low, ymax = high))

# use parasitic load to recalculate gross_gen;
# compare artificial gross_gen vs. known gross_gen
# agg should not be negative!

# parasitic_load = (gross_generation_mwh - net_generation_mwh) / (capacity_mw * 8760)
# p = (g-n) / (c*8760)
# p(c*8760) = g-n
# p(c*8760) + n = g










#### Visualize parasitic_load ####
ParasiticLoadLong %>%
	filter(metric_type == 'fit') %>%
	select(model, metric_type, parasitic_load) %>%
	ggplot(aes(x = model, y = parasitic_load)) +
	geom_boxplot(outlier.alpha = 0.3, outlier.color = 'dodgerblue') +
	coord_flip() +
	scale_x_discrete(limits = rev) +
	labs(x = '', y = 'Fitted parasitic load', title = 'Distribution of fitted parasitic load') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.y = element_blank(),
		text = element_text(family = 'serif')
	)

ParasiticLoadLong %>%
	filter(metric_type == 'fit') %>%
	select(model, parasitic_load) %>%
	group_by(model) %>%
	skim(parasitic_load) %>%
	select(-skim_variable, -skim_type, -numeric.hist, -n_missing, -complete_rate) %>%
	rename_all(str_replace, 'numeric.p', 'percentile_') %>%
	rename(mean = numeric.mean, sd = numeric.sd) %>%
	mutate_if(is.numeric, round, 2) %>%
	write_csv('results/parasitic_load')

# rules to apply to fitted values:
# Check: gross_generation_mwh cannot be <0 (MOST IMPORTANT CHECK)
MinYFit <-
	Results %>%
		group_by(model) %>%
		summarize(
			min_y_fit = min(y_fit),
			prop_y_fit_below_zero = mean(y_fit < 0)
		) %>%
		ungroup
print(MinYFit)
write_csv(MinYFit, 'results/min_y_fit.csv')

MinYFit %>%
	ggplot(aes(x = model, y = prop_y_fit_below_zero)) +
	geom_col(fill = 'maroon') +
	coord_flip(y = c(0, 1)) +
	geom_label(aes(label = scales::percent(prop_y_fit_below_zero)), family = 'serif', nudge_y = 0.05) +
	scale_y_continuous(labels = scales::percent_format()) +
	scale_x_discrete(limits = rev) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.y = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = '', y = '', title = 'Percentage of fitted gross_generation_mwh\nthat is below 0')

min_check <- all(MinYFit$min_y_fit >= 0)
str_c('Check 1: gross_generation_mwh cannot be negative: ', min_check)

# Check: gross_generation_mwh should be at or higher than net generation_mwh
# (ie parasitic load should be zero or positive)

PropParasiticLoadIsNeg <-
	ParasiticLoadLong %>%
		filter(metric_type == 'fit') %>%
		select(model, parasitic_load) %>%
		group_by(model) %>%
		summarize(prop_below_zero = mean(parasitic_load < 0)) %>%
		ungroup
PropParasiticLoadIsNeg %>%
	write_csv('results/prop_parasitic_load_neg.csv')

PropGrossGenerationAtOrGreaterThanNetGeneration <-
	ParasiticLoadLong %>%
		filter(metric_type == 'fit') %>%
		group_by(model) %>%
		summarize(prop_gross_generation_at_or_greater_than_net_generation = mean(gross_generation_mwh >= net_generation_mwh)) %>%
		ungroup

PropGrossGenerationAtOrGreaterThanNetGeneration %>%
	ggplot(aes(x = model, y = prop_gross_generation_at_or_greater_than_net_generation)) +
	geom_col() +
	coord_flip(ylim = c(0, 1)) +
	scale_x_discrete(limits = rev) +
	scale_y_continuous(labels = scales::percent_format(1)) +
	labs(x = '', y = '', title = 'How often is gross_generation_mwh greater than,\nor equal to, net_generation_mwh?') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.y = element_blank(),
		text = element_text(family = 'serif')
	)

# gross_generation_mwh distribution should look like net_generation_mwh, but shifted to the right a bit (diff is parasitic_load)
ParasiticLoadLong %>%
	filter(metric_type == 'fit') %>%
	select(model, net_generation_mwh, gross_generation_mwh) %>%
	gather(variable, value, -model) %>%
	ggplot(aes(x = variable, y = value)) +
	geom_boxplot(outlier.alpha = 0.3, outlier.color = 'dodgerblue') +
	facet_wrap(~model, ncol = 1) +
	coord_flip() +
	scale_x_discrete(limits = rev) +
	scale_y_continuous(labels = scales::comma_format(1)) +
	labs(x = '', y = '', title = 'Fitted gross_generation_mwh, compared with\nnet_generation_mwh distribution') +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.y = element_blank(),
		text = element_text(family = 'serif')
	)
