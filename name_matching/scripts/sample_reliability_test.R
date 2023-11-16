library(tidyverse)
library(skimr)
# library(effsize)

# Mapping rate
# Count per type
# 	and over time
# capacity per type
# 	and over time

#### Load data ####
Pudl <- read_csv('clean_data/pudl.csv', col_types = cols(
	plant_id_eia = 'c', report_year = 'i', match_type = 'f'
)) %>%
	mutate_if(is.character, trimws) %>%
	mutate(
		plant_type = str_to_lower(plant_type),
		plant_type = str_replace_all(plant_type, '_', ' ')
	)

Rmi <- read_csv('clean_data/rmi.csv', col_types = cols(
	report_year = 'i'
)) %>%
	drop_na(plant_name_ferc) %>%
	mutate_if(is.character, trimws) %>%
	rename(technology_1 = `Technology 1`, plant_type_raw = plant_kind)

PlantTypes <- read_csv('clean_data/plant_types.csv', col_types = 'cc') %>%
	relocate(key) %>%
	rename(plant_type_raw = key, plant_type_clean = value) %>%
	mutate(
		plant_type_clean = if_else(
			plant_type_clean == 'na category', NA_character_, plant_type_clean
		),
	) %>%
	mutate_all(str_to_lower)

#### Clean RMI ####
RmiClean <-
	Rmi %>%
		mutate(plant_type_raw = str_to_lower(plant_type_raw)) %>%
		left_join(PlantTypes, by = 'plant_type_raw') %>%
		mutate(
			plant_type = coalesce(plant_type_clean, plant_type_raw)
		) %>%
		select(
			plant_name_ferc,
			plant_id_eia,
			report_year,
			tot_capacity,
			technology_1,
			# plant_type_raw,
			# plant_type_clean,
			plant_type
		)

#### Join data, lump smaller plant types ####
JoinMePudl <-
	Pudl %>%
		rename(capacity = capacity_mw_ferc1) %>%
		mutate(model = 'PUDL') %>%
		select(model, plant_id_eia, report_year, capacity, plant_type)

JoinMeRmi <-
	RmiClean %>%
		rename(capacity = tot_capacity) %>%
		mutate(model = 'RMI') %>%
		select(model, plant_id_eia, report_year, capacity, plant_type)

Data <-
	JoinMePudl %>%
		bind_rows(JoinMeRmi) %>%
		relocate(model, report_year) %>%
		filter(report_year >= 2006L) %>%
		arrange(model, report_year) %>%
		mutate(
			plant_type_fac = fct_lump_n(plant_type, 5L, other_level = '(Other)'),
			plant_type_fac = fct_explicit_na(plant_type_fac),
			plant_type_fac = fct_infreq(plant_type_fac),
			plant_id_eia_fac = if_else(
				is.na(plant_id_eia),
				'(Missing)',
				'Plant ID EIA match'),
			plant_id_eia_fac = factor(plant_id_eia_fac,
																levels = c('Plant ID EIA match', '(Missing)')
			)
		) %>%
	mutate_if(is.character, as.factor)

#### Mapping rate ####
# 1. count
Rmi %>%
	mutate(plant_type_raw = str_to_lower(plant_type_raw)) %>%
	left_join(PlantTypes, by = 'plant_type_raw') %>%
	mutate(
		plant_type_raw_fac = if_else(is.na(plant_type_raw), '(Missing)', 'Exists'),
		plant_type_clean_fac = if_else(is.na(plant_type_clean), '(Missing)', 'Exists'),
		plant_type_raw_fac = factor(plant_type_raw_fac, levels = c('(Missing)', 'Exists')),
		plant_type_clean_fac = factor(plant_type_clean_fac, levels = c('(Missing)', 'Exists')),
	) %>%
	count(plant_type_raw_fac, plant_type_clean_fac, .drop = F) %>%
	ggplot(aes(x = plant_type_clean_fac, y = plant_type_raw_fac, fill = n, label = scales::comma(n))) +
	geom_raster() +
	geom_text() +
	scale_fill_gradient(low = "white", high = "blue") +
	scale_x_discrete(position = "top", limits = rev) +
	labs(x = 'Clean', y = 'Original', title = 'RMI') +
	theme_bw() +
	theme(
		text = element_text(family = 'serif'),
		axis.ticks=element_blank(),
		panel.grid = element_blank(),
		legend.position = 'none'
	)

# 2. longitudinal
Rmi %>%
	mutate(plant_type_raw = str_to_lower(plant_type_raw)) %>%
	left_join(PlantTypes, by = 'plant_type_raw') %>%
	mutate(
		plant_type_raw_fac = if_else(is.na(plant_type_raw), '(Missing)', 'Exists'),
		plant_type_clean_fac = if_else(is.na(plant_type_clean), '(Missing)', 'Exists'),
		result = case_when(
			plant_type_clean_fac == 'Exists' ~ 'Clean',
			plant_type_raw_fac == 'Exists' ~ 'Original',
			T ~ 'Unknown'
		),
		result = factor(result, levels = c('Clean', 'Original', 'Unknown'))
	) %>%
	count(report_year, result, .drop = F) %>%
	ggplot(aes(x = report_year, y = n, fill = result, group = result)) +
	geom_col(position = 'dodge') +
	theme(
		axis.ticks = element_blank(),
		legend.position = 'bottom',
		text = element_text(family = 'serif')
	) +
	labs(x = 'Report year', fill = '', title = 'RMI mapping strategies')

Rmi %>%
	mutate(plant_type_raw = str_to_lower(plant_type_raw)) %>%
	left_join(PlantTypes, by = 'plant_type_raw') %>%
	mutate(
		plant_type_raw_fac = if_else(is.na(plant_type_raw), '(Missing)', 'Exists'),
		plant_type_clean_fac = if_else(is.na(plant_type_clean), '(Missing)', 'Exists'),
		result = case_when(
			plant_type_clean_fac == 'Exists' ~ 'Clean',
			plant_type_raw_fac == 'Exists' ~ 'Original',
			T ~ 'Unknown'
		),
		result = factor(result, levels = c('Clean', 'Original', 'Unknown'))
	) %>%
	count(report_year, result, .drop = F) %>%
	ggplot(aes(x = report_year, y = n, fill = result, group = result)) +
	geom_col(position = 'dodge') +
	facet_wrap(~result, ncol = 1, scales = 'free_y') +
	theme(
		axis.ticks = element_blank(),
		legend.position = 'bottom',
		text = element_text(family = 'serif')
	) +
	labs(x = 'Report year', fill = '', title = 'RMI mapping strategies')

#### Counts for both ####
# counts
Data %>%
	count(model, plant_type_fac, plant_id_eia_fac, .drop = F) %>%
	ggplot(aes(x = plant_type_fac, y = n, fill = plant_id_eia_fac, group = plant_id_eia_fac)) +
	geom_col(position = 'dodge') +
	facet_wrap(~model) +
	coord_flip() +
	scale_x_discrete(limits = rev) +
	theme(
		axis.ticks = element_blank(),
		legend.position = 'bottom',
		text = element_text(family = 'serif')
	) +
	labs(
		x = 'Plant type',
		y = 'n',
		title = 'FERC:EIA matches by plant type',
		fill = ''
	) +
	scale_fill_manual(values = c('darkgrey', 'maroon'))


# longitudinal
Data %>%
	count(report_year, model, plant_type_fac, plant_id_eia_fac, .drop = F) %>%
	ggplot(aes(x = report_year, fill = plant_id_eia_fac, group = plant_id_eia_fac, y = n)) +
	geom_col(position = 'dodge') +
	facet_grid(model ~ plant_type_fac) +
	theme(
		axis.ticks = element_blank(),
		legend.position = 'bottom',
		text = element_text(family = 'serif')
	) +
	labs(
		x = 'Plant type',
		y = 'n',
		title = 'FERC:EIA matches by plant type',
		fill = ''
	) +
	scale_fill_manual(values = c('darkgrey', 'maroon'))

#### Capacity ####
# over all

Data %>%
	group_by(model, plant_type_fac) %>%
	summarize(sum_capacity = sum(capacity)) %>%
	ungroup %>%
	ggplot(aes(x = plant_type_fac, fill = model, group = model, y = sum_capacity)) +
	geom_col(position = 'dodge') +
	coord_flip() +
	scale_x_discrete(limits = rev) +
	scale_fill_discrete(limits = rev) +
	scale_y_continuous(labels = scales::comma_format()) +
	theme(
		axis.ticks = element_blank(),
		legend.position = 'bottom',
		text = element_text(family = 'serif')
	) +
	labs(
		x = 'Plant type',
		y = 'Total capacity (MW)',
		fill = '',
		title = 'Capacity by plant type'
	)

# longitudinal
Data %>%
	group_by(report_year, model, plant_type_fac, .drop = F) %>%
	summarize(sum_capacity = sum(capacity)) %>%
	ungroup %>%
	ggplot(aes(x = report_year, group = model, fill = model, y = sum_capacity)) +
	geom_col(position = 'dodge') +
	facet_wrap(~plant_type_fac) +
	# scale_fill_discrete(limits = rev) +
	scale_y_continuous(labels = scales::comma_format()) +
	theme(
		axis.ticks = element_blank(),
		legend.position = 'bottom',
		text = element_text(family = 'serif')
	) +
	labs(
		x = 'Report year',
		y = 'Total capacity (MW)',
		fill = '',
		title = 'Capacity by plant type, over time'
	)
