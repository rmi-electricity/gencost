library(tidyverse)
library(skimr)
set.seed(1)

#### Load data ####

# Note that MapIdToName is NOT a 1:1 mapping
MapIdToName <- read_csv('clean_data/map_id_to_name.csv', col_types = 'cc')

# MapIdToName %>%
# 	mutate(plant_name_eia = str_to_lower(plant_name_eia)) %>%
# 	filter(str_detect(plant_name_eia, 'columbia')) %>%
# 	arrange(plant_name_eia) %>%
# 	as.data.frame
#

Pudl <- read_csv('clean_data/pudl.csv', col_types = cols(report_year = 'i', .default = 'c')) %>%
	distinct(plant_id_eia, plant_name_eia, plant_name_ferc, report_year)

RmiNoId <- read_csv('clean_data/rmi.csv', col_types = cols(report_year = 'i', .default = 'c')) %>%
	select(-`...1`)
Rmi <-
	RmiNoId %>%
		drop_na(plant_name_ferc) %>%
		left_join(MapIdToName, by = 'plant_id_eia')

#### Look at agreements ####
# We can only use rows in which EACH model's dataset only lists (plant_name_ferc & report_year) once,
# and we have to exclude plants that have a 1:many mapping of id's to names
JoinMeRmi <-
	Rmi %>%
		rename(plant_name_eia_rmi = plant_name_eia, plant_id_eia_rmi = plant_id_eia) %>%
		select(report_year, plant_name_ferc, plant_id_eia_rmi) %>%
		distinct

JoinMePudl <-
	Pudl %>%
		rename(plant_name_eia_pudl = plant_name_eia, plant_id_eia_pudl = plant_id_eia) %>%
		select(report_year, plant_name_ferc, plant_id_eia_pudl) %>%
		distinct

SemiJoinMeRmi <-
	JoinMeRmi %>%
		count(plant_name_ferc, report_year) %>%
		filter(n == 1L) %>%
		select(plant_name_ferc, report_year)

SemiJoinMePudl <-
	JoinMePudl %>%
		count(plant_name_ferc, report_year) %>%
		filter(n == 1L) %>%
		select(plant_name_ferc, report_year)

Joined <-
	inner_join(
		JoinMeRmi %>%
			semi_join(SemiJoinMeRmi, by = c('report_year', 'plant_name_ferc')),
		JoinMePudl %>%
			semi_join(SemiJoinMePudl, by = c('report_year', 'plant_name_ferc')),
		by = c('report_year', 'plant_name_ferc')
	)

# Analyze joined
Joined %>%
	count(report_year, plant_name_ferc) %>%
	pull(n) %>%
	all(. == 1L)

Joined %>%
	mutate(is_name_agreed = plant_id_eia_rmi == plant_id_eia_pudl) %>%
	count(is_name_agreed)

Joined %>%
	mutate(
		is_pudl_na = is.na(plant_id_eia_pudl),
		is_rmi_na = is.na(plant_id_eia_rmi),
		is_pudl_na = factor(is_pudl_na, levels = c(T, F)),
		is_rmi_na = factor(is_rmi_na, levels = c(T, F)),
	) %>%
	count(is_pudl_na, is_rmi_na, .drop = F)

MapPudl <-
	MapIdToName %>%
		rename(plant_id_eia_pudl = plant_id_eia, plant_name_eia_pudl = plant_name_eia)

MapRmi <-
	MapIdToName %>%
		rename(plant_id_eia_rmi = plant_id_eia, plant_name_eia_rmi = plant_name_eia)

Sample <-
	Joined %>%
	rowid_to_column() %>%
	sample_n(1000)

Sample %>%
	write_csv('clean_data/sample.csv')

Sample %>%
	mutate(
		is_disagreement = is.na(plant_id_eia_rmi)
			| is.na(plant_id_eia_pudl)
			| (plant_id_eia_rmi != plant_id_eia_pudl)
 	) %>%
	left_join(MapPudl, by = 'plant_id_eia_pudl') %>%
	left_join(MapRmi, by = 'plant_id_eia_rmi') %>%
	mutate(
		is_rmi_right = if_else(!is_disagreement, 1L, NA_integer_),
		is_pudl_right = if_else(!is_disagreement, 1L, NA_integer_),
	) %>%
	select(
		"rowid",
		"is_disagreement",
		"report_year",
		"plant_name_ferc",
		"plant_id_eia_rmi",
		"plant_id_eia_pudl",
		"plant_name_eia_rmi",
		"is_rmi_right",
		"plant_name_eia_pudl",
		"is_pudl_right"
	) %>%
	arrange(is_disagreement, rowid) %>%
	write_csv('clean_data/sample_for_qc.csv')
