# data_for_pf_subplants.parquet imputation project
# 1_a: ELT with raw variables
# Andrew Bartnof, RMI April 2023

library(tidyverse)
library(arrow)
library(skimr)
library(conflicted)
library(psych)
library(GGally)
# library(polycor)
# library(mclust)
# library(mice)
# library(readxl)
conflict_prefer("map", "purrr")
conflict_prefer("map2", "purrr")
conflict_prefer("filter", "dplyr")
set.seed(1)

get_variables_with_variance <- function(X){
	X %>%
		# select(-prime_mover) %>%
		summarize_all(sd, na.rm = T) %>%
		gather(variable, sd) %>%
		filter(sd > 0) %>%
		pull(variable)
}

# Function to return points and geom_smooth
# allow for the method to be changed
custom_function = function(data, mapping, method = "lm", ...){
# https://stackoverflow.com/questions/22671686/how-to-draw-loess-estimation-in-ggally-using-ggpairs
	p = ggplot(data = data, mapping = mapping) + 
		geom_smooth(method=method, ...)
	p
}

# Note the variables that are sensible to model:
# https://rockmtnins.sharepoint.com/:x:/r/sites/UTF/_layouts/15/Doc.aspx?sourcedoc=%7B8CDB80F6-FB7E-4B3F-B58D-920C84572EC8%7D&file=data_classes__data_for_pf_subplants.xlsx&action=default&mobileredirect=true&DefaultItemOpen=1&login_hint=abartnof.contractor%40RMI.org&ct=1683136643816&wdOrigin=OFFICECOM-WEB.MAIN.EDGEWORTH&cid=314b8194-4bfb-4c41-a868-08742df6ba63&wdPreviousSessionSrc=HarmonyWeb&wdPreviousSession=1b8e11b9-febc-4c5d-9284-fffad50b6be7
variables_to_select <- c(
'prime_mover',
'age_relative_to_average',
# 'age_relative_to_average2',
'associated_combined_heat_power',
'average_age_in_report_year',
'biofuel_gross_cf',
'bypass_heat_recovery',
'carbon_capture',
'capacity_mw', # we want to visualize this
'coal_gross_cf',
'duct_burners',
'final_gen_type',
'fluidized_bed_tech',
'fuel_category',
'generator_starts',
'gross_cf',
'natural_gas_gross_cf',
'other_combustion_tech',
'other_gas_gross_cf',
'other_gross_cf',
'petroleum_coke_gross_cf',
'petroleum_gross_cf',
'pollution_control_costs_per_kw',
'pulverized_coal_tech',
'rmi_fuel_group_1',
'rmi_fuel_group_2',
'rmi_fuel_group_3',
'sector',
'stoker_tech',
'subcritical_tech',
'supercritical_tech',
'ultrasupercritical_tech'
)
#### ELT ####
# select only variables that we want to model
setwd('~/Documents/rmi/gencost/exploration_of_power_plant_characteristics/')

RawData <-
	read_parquet('input_data/data_for_pf_subplants.parquet') %>%
	select(all_of(variables_to_select)) %>%
	rowid_to_column() %>%
	mutate(rowid = as.character(rowid))

write_rds(RawData, file = 'clean_data/RawData.RDS')

# AS IS:
# rowid
# prime_mover

# DUMMY CODE:
# final_gen_type
# fuel_category
# rmi_fuel_group_1
# rmi_fuel_group_2
# rmi_fuel_group_3 
# sector              

DummyFinalGenType <-
	psych::dummy.code(RawData$final_gen_type) %>%
	as_tibble %>%
	rename_all(function(x){paste0("final_gen_type__", x)})

DummyFuelCategory <-
	psych::dummy.code(RawData$fuel_category) %>%
	as_tibble %>%
	rename_all(function(x){paste0("fuel_category__", x)})

DummyRmiFuelGroup1 <-
	psych::dummy.code(RawData$rmi_fuel_group_1)	%>%
	as_tibble %>%
	rename(missing_value = V6) %>%
	rename_all(function(x){paste0("rmi_fuel_group_1__", x)})

DummyRmiFuelGroup2 <-	
	psych::dummy.code(RawData$rmi_fuel_group_2)	%>%
	as_tibble %>%
	rename_all(function(x){paste0("rmi_fuel_group_2__", x)})

DummyRmiFuelGroup3 <-
	psych::dummy.code(RawData$rmi_fuel_group_3)	%>%
	as_tibble %>%
	rename_all(function(x){paste0("rmi_fuel_group_3__", x)})

DummySector <-
	psych::dummy.code(RawData$sector)	%>%
	as_tibble %>%
	rename_all(function(x){paste0("sector__", x)})

EncodedData <-
	RawData %>% 
		bind_cols(DummyFinalGenType, DummyFuelCategory, DummyRmiFuelGroup1,
							DummyRmiFuelGroup2, DummyRmiFuelGroup3, DummySector) %>%
		select(-final_gen_type, -fuel_category, -rmi_fuel_group_1, 
					 -rmi_fuel_group_2, -rmi_fuel_group_3, -sector)

NumericData <- 
	EncodedData %>%
	select(-rowid)

#### EDA PCA ####
NestedForPcaEda <-
# Resample the data in order to understand how many PCA we'll need
	NumericData %>%
		group_by(prime_mover) %>%
		nest %>%
		expand_grid(resample_num = 1:200) %>%
		mutate(
			data = map(data, ~sample_frac(tbl = ., size = 0.5, replace = T)),
			variables_with_variance = map(data, get_variables_with_variance),
			data = map2(data, variables_with_variance, ~select(.x, all_of(.y))),
			data_scaled = map(data, scale),
			data_scaled = map(data, as.vector),
			data_scaled = map(data_scaled, ~mutate_all(., replace_na, 0.0)),
		) %>%
	select(prime_mover, resample_num, data_scaled)
saveRDS(NestedForPcaEda, 'clean_data/nested_for_pca_eda.RDS')
# NestedForPcaEda <- readRDS('clean_data/nested_for_pca_eda.RDS')

PcaEda <-
	NestedForPcaEda %>%
		mutate(
			parallel_test = map(data_scaled, fa.parallel, fa = 'pc', plot = F),
			ncomp = map_dbl(parallel_test, 'ncomp')
		) %>%
		select(-parallel_test)
saveRDS(PcaEda, 'clean_data/pca_eda.RDS')
PcaEda
# PcaEda <- readRDS('clean_data/pca_eda.RDS')

PcaEda %>%
	count(prime_mover, ncomp) %>%
	group_by(prime_mover) %>%
	mutate(
		prop = n / sum(n),
		is_highest = prop == max(prop)
		) %>%
	ungroup %>%
	ggplot(aes(x = ncomp, y = prop)) +
	geom_col(aes(fill = is_highest)) +
	scale_fill_manual(values = c('grey40', 'darkblue')) +
	scale_x_continuous(breaks = seq(1L, 20L)) +
	scale_y_continuous(labels = scales::percent_format(1),
										 breaks = seq(0, 1, by = 0.25)) +
	facet_wrap(~prime_mover, ncol = 1) +
	labs(x = 'Number of components (PCA)', y = '% of times when the parallel test chose this',
			 title = 'Bootstrapped PCA results',
			 caption = '200 resamples, taking 50% of the data, with replacement') +
	theme(
		text = element_text(family = 'serif'),
		axis.ticks = element_blank(),
		legend.position = 'none',
		panel.grid.minor.x = element_blank()
	) 

PcaEda %>%
	group_by(prime_mover) %>%
	summarize(median_ncomp = median(ncomp)) %>%
	ungroup

# CC: 7
# GT: 8
# ST: 15

#### PCA ####
PcaCC <-
	NumericData %>% 
	filter(prime_mover == 'CC') %>%
	select_if(is.numeric) %>%
	select(., get_variables_with_variance(.)) %>%
	mutate_all(scale) %>%
	mutate_all(as.vector) %>%
	mutate_all(replace_na, 0) %>%
	pca(nfactors = 7, rotate = 'promax')

PcaGT <-
	NumericData %>% 
	filter(prime_mover == 'GT') %>%
	select_if(is.numeric) %>%
	select(., get_variables_with_variance(.)) %>%
	mutate_all(scale) %>%
	mutate_all(as.vector) %>%
	mutate_all(replace_na, 0) %>%
	pca(nfactors = 8, rotate = 'promax')

PcaST <-
	NumericData %>% 
	filter(prime_mover == 'ST') %>%
	select_if(is.numeric) %>%
	select(., get_variables_with_variance(.)) %>%
	mutate_all(scale) %>%
	mutate_all(as.vector) %>%
	mutate_all(replace_na, 0) %>%
	pca(nfactors = 15, rotate = 'promax')
#

#### Clustering ####
ScoresCC <-
	PcaCC$scores %>%
		as_tibble %>%
		mutate(prime_mover = 'CC')
ScoresST <-
	PcaST$scores %>%
		as_tibble %>%
		mutate(prime_mover = 'ST')
ScoresGT <-
	PcaGT$scores %>%
		as_tibble %>%
		mutate(prime_mover = 'GT')

# Error of each cluster
ResampledClusters <-
	bind_rows(
		ScoresCC %>%
			group_by(prime_mover) %>%
			nest,
		ScoresST %>%
			group_by(prime_mover) %>%
			nest,
		ScoresGT %>%
			group_by(prime_mover) %>%
			nest
	) %>%
	expand_grid(resample_num = 1:50, num_clusters = 1:10) %>%
	mutate(
		data = map(data, sample_frac, size = 1, replace = T),
		cls_mod = map2(data, num_clusters, ~kmeans(.x, centers = .y)),
		within_ss = map_dbl(cls_mod, 'tot.withinss'),
		tot_ss = map_dbl(cls_mod, 'totss'),
		within_over_total_ss = within_ss / tot_ss
	)
saveRDS(ResampledClusters, file = 'clean_data/resampled_clusters.RDS')
# ResampledClusters <- readRDS(file = 'clean_data/resampled_clusters.RDS')

ClsSigLabels <-
	# see if each num_clusters is significantly better than the prev
	ResampledClusters %>%
		select(prime_mover, num_clusters, within_over_total_ss) %>%
		group_by(prime_mover) %>%
		nest %>%
		mutate(ptt = map(data, ~with(., pairwise.t.test(
			x = within_over_total_ss, g = num_clusters,
			paired = T, p.adjust.method = 'bonferroni'))),
					 P = map(ptt, 'p.value'),
					 P = map(P, as.data.frame),
					 P = map(P, rownames_to_column, var = 'var1')
					 ) %>%
		select(prime_mover, P) %>%
		unnest(P) %>%
		ungroup %>%
		gather(var2, p, -prime_mover, -var1) %>%
		mutate_at(c('var1', 'var2'), parse_integer) %>%
		group_by(prime_mover) %>%
		filter(var1 - 1 == var2) %>%
		ungroup %>%
		mutate(is_sig = p < 0.05,
					 sig_label = if_else(is_sig, '*', 'NS')) %>%
		arrange(prime_mover, var1) %>%
		select(prime_mover, num_clusters = var1, sig_label)
#	
PlotmeResampledClusters <-
	ResampledClusters %>%
		select(prime_mover, num_clusters, within_ss, within_over_total_ss) %>%
		filter(num_clusters > 1) %>%
		group_by(prime_mover, num_clusters) %>%
		summarize(
			mean = mean(within_over_total_ss),
			low = mean(within_over_total_ss) - sd(within_over_total_ss),
			high = mean(within_over_total_ss) + sd(within_over_total_ss)
		) %>%
		ungroup
#	
	ggplot(data = PlotmeResampledClusters,
				 aes(x = num_clusters, y = mean)) +
	geom_point() +
	geom_line() +
	geom_segment(aes(x = num_clusters, xend = num_clusters, y = low, yend = high)) +
	geom_text(data = ClsSigLabels, y = 0.9, aes(label = sig_label), size = 3) +
	facet_wrap(~prime_mover) +
	coord_cartesian(ylim = c(0, 1), xlim = c(2, 10)) +
	scale_x_continuous(breaks = seq(1, 20, by = 1)) +
	theme(
		panel.grid.minor.x = element_blank(),
		axis.ticks = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = 'Number of clusters', y = 'Normalized within-cluster sum of squared error',
			 title = 'Error rates for the k-mean clusters',
			 caption = '500 resamples\nSignificance is judged with paired t-tests using Bonferroni correction\nError bars indicate +/- 1 standard deviation')

#### Create and save classifications ####
	# [2, 5]
NumPcaComponents <-
	tribble(		
		~prime_mover, ~num_pca_components,
		'CC', 7L,
		'GT', 8L,
		'ST', 15L
	)

PcaFit <-
	# Fit PCAs to the whole data set so that we can attach PCA 
	# scores to rowids
	EncodedData %>%
		group_by(prime_mover) %>%
		nest %>%
		left_join(NumPcaComponents, by = 'prime_mover') %>%
		mutate(
			rowid = map(data, ~select(., 'rowid')),
			data = map(data, ~select(., -rowid)),
			variables_to_select = map(data, get_variables_with_variance),
			data = map2(data, variables_to_select, ~select(.x, all_of(.y))),
			data = map(data, mutate_all, scale),
			data = map(data, mutate_all, as.vector),
			data = map(data, mutate_all, replace_na, 0.0),
			pca_fit = map2(data, num_pca_components, 
									 ~pca(.x, nfactors = .y, rotate = 'promax', cor = 'cor')),
			scores = map(pca_fit, 'scores'),
			loadings = map(pca_fit, 'loadings')
		) %>%
		ungroup %>%
		select(prime_mover, rowid, num_pca_components, scores, loadings)
		
ClsOptions <-
	# This gives us the KMEANS classifications, per row, per # of classes; 
	# should be joined to initial data
	PcaFit %>%
		select(-loadings, -num_pca_components) %>%
		expand_grid(num_clusters = 2:5) %>%
		mutate(scores = map(scores, as.data.frame),
					 cls_fit = map2(scores, num_clusters, ~kmeans(x = .x, centers = .y)),
					 cls = map(cls_fit, 'cluster'),
		) %>%
		select(prime_mover, rowid, num_clusters, cls) %>%
		unnest(c(rowid, cls))

ExpectedValuesPerCls <-
	# Find the aggregate values per cluster, per clustering schema
	EncodedData %>%
		gather(variable, value, -rowid, -prime_mover) %>%
		group_by(prime_mover, variable) %>%
		mutate(
			value = as.vector(scale(value)),
			value = replace_na(value, 0.0)  # keep this?
		) %>%
		ungroup %>%
		left_join(ClsOptions, by = c('rowid', 'prime_mover')) %>%
		group_by(prime_mover, variable, num_clusters, cls) %>%
		summarize(avg = mean(value)) %>%
		ungroup
	#	
NoteworthyRanges <-
	# find places where the range isn't so interesting
	ExpectedValuesPerCls %>%
		group_by(prime_mover, variable, num_clusters) %>%
		summarize(range = max(avg) - min(avg)) %>%
		ungroup %>%
		mutate(is_range_noteworthy = range > 0.5)
	#	

cls_with_greatest_sse <-
	ExpectedValuesPerCls %>%	
		inner_join(NoteworthyRanges, by = c('prime_mover', 'variable', 'num_clusters')) %>%
		filter(prime_mover == 'CC', num_clusters == 3L, range > 0) %>%
		group_by(cls) %>%
		summarize(sse = sum(avg**2)) %>%
		ungroup %>%
		slice(which.max(sse)) %>%
		pull(cls)
	#
# GGpairs

# Don't visualize dummy-coded!
# all prime movers should have these modelled: 
# gross_cf
# generator_starts
# capacity_factor (where is this)
# capacity_mw (where is this)
# fuel_category
# average_age_in_report_year
# ...+ 2 more variables

# CC
# average_age_in_report_year
# sector
# make the variables z-scored

variables_to_select <- c('gross_cf', 'generator_starts', 
												 'capacity_mw',
												 'average_age_in_report_year')
												 # 'capacity_factor', 
												 # 'capacity_mw', 
												 # 'sector', 'fuel_category', 

X <-
	EncodedData %>%
		filter(prime_mover == 'CC') %>%
		select(rowid, all_of(variables_to_select)) %>%
		# mutate_if(is.numeric, ~as.vector(scale(.))) %>%
		inner_join(ClsOptions, by = 'rowid') %>%
		filter(num_clusters == 2) %>%
		select(-prime_mover, -rowid, -num_clusters) %>%
		mutate(cls = factor(cls))

variables_to_plot <- X %>%
		select(-cls) %>%
		colnames %>%
		sort

custom_lm = function(data, mapping,method = 'lm', se = FALSE,...){
	# visualization for lower triangle
# https://stackoverflow.com/questions/22671686/how-to-draw-loess-estimation-in-ggally-using-ggpairs
	p = ggplot(data = data) + 
		# geom_point(mapping, alpha = 0.1) +
		geom_smooth(mapping, method='lm', se = FALSE)
	p
}

X %>%
	ggpairs(aes(color = cls, group = cls), 
					columns = variables_to_plot,
					# switch = 'y',
					diag = list(continuous = wrap('densityDiag', alpha = 0.75)),
					# lower = list(continuous = wrap(lm_and_density)),
					upper = list(continuous = wrap(
						'cor', stars = T, digits = 1, use = 'pairwise.complete.obs')),
					lower = list(continuous = custom_lm)
					) +
	theme(
		text = element_text(family = 'serif'),
		axis.ticks = element_blank(),
		strip.text.y.right = element_text(angle = 0)
	) +
	labs(title = 'CC, 2 clusters')

# Same thing but with 3 clusters
X <-
	EncodedData %>%
		filter(prime_mover == 'CC') %>%
		select(rowid, all_of(variables_to_select)) %>%
		# mutate_if(is.numeric, ~as.vector(scale(.))) %>%
		inner_join(ClsOptions, by = 'rowid') %>%
		filter(num_clusters == 3) %>%
		select(-prime_mover, -rowid, -num_clusters) %>%
		mutate(cls = factor(cls))

variables_to_plot <- X %>%
		select(-cls) %>%
		colnames %>%
		sort

X %>%
	ggpairs(aes(color = cls, group = cls), 
					columns = variables_to_plot,
					# switch = 'y',
					diag = list(continuous = wrap('densityDiag', alpha = 0.75)),
					# lower = list(continuous = wrap(lm_and_density)),
					upper = list(continuous = wrap(
						'cor', stars = T, digits = 1, use = 'pairwise.complete.obs')),
					lower = list(continuous = custom_lm)
					) +
	theme(
		text = element_text(family = 'serif'),
		axis.ticks = element_blank(),
		strip.text.y.right = element_text(angle = 0)
	) +
	labs(title = 'CC, 3 clusters')

