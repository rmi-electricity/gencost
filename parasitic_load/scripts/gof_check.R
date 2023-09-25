library(tidyverse)
library(skimr)
library(Metrics)

# Part 1: load python models

PythonTest <-
	list.files(path = 'clean_data_py/test/', pattern = '.csv', full.names = T) %>%
		enframe(name = NULL, value = 'fn') %>%
		mutate(
			fold_num = parse_integer(str_extract(fn, '[0-9]+')),
			data = map(fn, read_csv),
			prime_mover = map(data, 'prime_mover'),
			gross_generation_mwh = map(data, 'gross_generation_mwh'),
			net_generation_mwh = map(data, 'net_generation_mwh'),
			capacity_mw = map(data, 'capacity_mw')
		) %>%
	select(fold_num, data, gross_generation_mwh, net_generation_mwh, capacity_mw, prime_mover)

# Null model

NullModels <-
	PythonTest %>%
		mutate(
			parasitic_load = map(data, 'parasitic_load'),
			Mean = map_dbl(parasitic_load, mean),
			Median = map_dbl(parasitic_load, median)
		) %>%
	select(-data) %>%
	gather(model, y_fit, -fold_num, -gross_generation_mwh, -net_generation_mwh, -capacity_mw, -parasitic_load, -prime_mover) %>%
	unnest(everything()) %>%
	rename(y_true = parasitic_load)


# SVM Poly
YFitSvmPoly <-
	list.files(path = 'results/svm poly/', full.names = T) %>%
		enframe(name = NULL, value = 'fn') %>%
		mutate(
			fold_num = parse_integer(str_extract(fn, '(?<=fold_)[0-9]')),
			YFit = map(fn, read_csv)
		) %>%
	select(fold_num, YFit)

SvmPoly <-
	PythonTest %>%
		left_join(YFitSvmPoly, by = 'fold_num') %>%
		select(-fold_num, -data) %>%
		unnest(everything()) %>%
		select(-`...1`) %>%
		mutate(model = 'SVM Polynomial') %>%
		select(model, fold_num, gross_generation_mwh, net_generation_mwh,
					 capacity_mw, y_fit, y_true, prime_mover
		)
SvmPoly

# SVM Linear
YFitSvmLinear <-
	list.files(path = 'results/svm linear/', full.names = T, pattern = 'csv') %>%
		enframe(name = NULL, value = 'fn') %>%
		mutate(
			fold_num = parse_integer(str_extract(fn, '(?<=fold_num_)[0-9]')),
			YFit = map(fn, read_csv)
		) %>%
	select(fold_num, YFit)

SvmLinear <-
	PythonTest %>%
		left_join(YFitSvmLinear, by = 'fold_num') %>%
		select(-fold_num, -data) %>%
		unnest(everything()) %>%
		select(-`...1`) %>%
		mutate(model = 'SVM Linear') %>%
		select(model, fold_num, gross_generation_mwh, net_generation_mwh,
					 capacity_mw, y_fit, y_true, prime_mover
		)

# Random Forest
YFitRandomForest <-
	list.files(path = 'results/random forest/', full.names = T) %>%
		enframe(name = NULL, value = 'fn') %>%
		mutate(
			fold_num = parse_integer(str_extract(fn, '(?<=fold_num_)[0-9]+')),
			YFit = map(fn, read_csv)
		)

RandomForest <-
	PythonTest %>%
		left_join(YFitRandomForest, by = 'fold_num') %>%
		select(-fold_num, -data) %>%
		unnest(everything()) %>%
		select(-`...1`) %>%
		select(model, fold_num, gross_generation_mwh, net_generation_mwh,
					 capacity_mw, y_fit, y_true, prime_mover
		)

# PreppedData <- readRDS('clean_data/prepped_data.RDS')

# PyOriginalData <-
# 	list.files(path = 'clean_data_py/test/', pattern = 'csv', full.names = T) %>%
# 		enframe(name = NULL, value = 'fn') %>%
# 		arrange(fn) %>%
# 		mutate(
# 			fold_num = str_extract(fn, '[0-9]+'),
# 			data = map(fn, read_csv)
# 		) %>%
# 		unnest(data) %>%
# 		select(-fn)

AllMods <-
		SvmLinear %>%
		bind_rows(SvmPoly) %>%
		bind_rows(RandomForest) %>%
		bind_rows(NullModels)

#### RMSE ####
AllMods %>%
	group_by(model, fold_num) %>%
	summarize(rmse = Metrics::rmse(y_fit, y_true)) %>%
	ungroup %>%
	ggplot(aes(x = model, y = rmse)) +
	geom_point() +
	coord_flip() +
	expand_limits(y = 0) +
	labs(x = '', y = 'RMSE')

AllMods %>%
	group_by(model, fold_num) %>%
	summarize(rmse = Metrics::rmse(y_fit, y_true)) %>%
	ungroup %>%
	group_by(model) %>%
	summarize(rmse = mean(rmse)) %>%
	ungroup %>%
	ggplot(aes(x = model, y = rmse)) +
	geom_point() +
	coord_flip() +
	expand_limits(y = 0) +
	labs(x = '', y = 'Mean RMSE')

AllMods %>%
	group_by(model) %>%
	summarize(
		Fit = mean(y_fit < 0),
		True = mean(y_true < 0),
		# prop_over_one_fit = mean(y_fit > 1),
		# prop_over_one_true = mean(y_true > 1),
	) %>%
	ungroup %>%
	gather(variable, prop, -model) %>%
	ggplot(aes(x = model, fill = variable, group = variable, y = prop)) +
	geom_col(position = 'dodge') +
	coord_flip() +
	scale_y_continuous(labels = scales::percent_format()) +
	labs(x = '', y = '', title = 'Parasitic load < 0.0', fill = '')

AllMods %>%
	group_by(model) %>%
	summarize(
		# Fit = mean(y_fit < 0),
		# True = mean(y_true < 0),
		Fit = mean(y_fit > 1),
		True = mean(y_true > 1),
	) %>%
	ungroup %>%
	gather(variable, prop, -model) %>%
	ggplot(aes(x = model, fill = variable, group = variable, y = prop)) +
	geom_col(position = 'dodge') +
	coord_flip() +
	scale_y_continuous(labels = scales::percent_format()) +
	labs(x = '', y = '', title = 'Parasitic load > 1.0', fill = '')

# use parasitic load to recalculate gross_gen;
# compare artificial gross_gen vs. known gross_gen
# agg should not be negative!

# parasitic_load = (gross_generation_mwh - net_generation_mwh)
#	/ (capacity_mw * 8760)
# p = (g-n) / (c*8760)
# p(c*8760) = g-n
# p(c*8760) + n = g

AllMods %>%
	mutate(
		artificial_gross_generation_mwh = y_fit * (capacity_mw * 8760) + net_generation_mwh,
		capacity_factor = artificial_gross_generation_mwh / (capacity_mw * 8760)
		) %>%
	ggplot(aes(x = model, y = capacity_factor)) +
	geom_boxplot(outlier.alpha = 0.1, outlier.color = 'blue') +
	geom_hline(yintercept = 1, linetype = 'dashed') +
	facet_wrap(~prime_mover)
	# filter(model == 'Random Forest') %>%
	# arrange(desc(artificial_gross_generation_mwh)) %>%
	# select(artificial_gross_generation_mwh)



AllMods %>%
	mutate(artificial_gross_generation_mwh = y_fit * (capacity_mw * 8760) + net_generation_mwh) %>%
	ggplot(aes(x = model, y = artificial_gross_generation_mwh)) +
	geom_boxplot()
	# geom_density() +
	# facet_wrap(~model)

AllMods %>%
	mutate(artificial_gross_generation_mwh = y_fit * (capacity_mw * 8760) + net_generation_mwh) %>%
	group_by(model) %>%
	skim(artificial_gross_generation_mwh)
