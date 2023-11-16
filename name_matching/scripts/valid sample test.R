library(tidyverse)
library(skimr)
set.seed(1)

# define functions
# https://stackoverflow.com/questions/2547402/how-to-find-the-statistical-mode
get_mode <- function(x) {
	ux <- unique(x)
	ux[which.max(tabulate(match(x, ux)))]
}

#### Load data ####
# Note that MapIdToName is NOT a 1:1 mapping
MapIdToName <- read_csv('clean_data/map_id_to_name.csv', col_types = 'cc')

Pudl <- read_csv('clean_data/pudl.csv', col_types = 'ddccccif') %>%
	mutate_if(is.character, trimws)

Rmi <- read_csv('clean_data/rmi.csv', col_types = 'iccid') %>%
	select(-1) %>%
	drop_na(plant_name_ferc) %>%
	mutate_if(is.character, trimws) %>%
	mutate(plant_id_eia = na_if(plant_id_eia, '<NA>'))
	distinct

Rmi %>%
	select(plant_name_ferc, plant_id_eia, tot_capacity) %>%  # tot_capacity seems to be a FERC figure, not EIA
	skim

# capacity_mw_ferc1 v capacity_mw_eia, where > 10k
	# do those rows match to EIA? what capacity does EIA have?
	# what capacity does Uday have for these rows?
	# are the capacities for these plants more sensible in other years?
	# Do both RMI and Pudl use them?

Pudl %>%
	filter(capacity_mw_ferc1 > 10000) %>%
	select(plant_name_ferc, report_year, capacity_mw_ferc1) %>%
	arrange(plant_name_ferc)

# There are 10 rows in Pudl (plant_name_ferc x report_year) where capacity_mw_ferc1 exceeds 10k
# No plant does this twice.
Pudl %>%
	filter(capacity_mw_ferc1 > 10000) %>%
	distinct(plant_name_ferc, report_year) %>%
	nrow

Pudl %>%
	filter(capacity_mw_ferc1 > 10000) %>%
	distinct(plant_name_ferc, report_year) %>%
	count(plant_name_ferc) %>%
	count(n)

# None where capacity_mw_eia exceeds 10k
Pudl %>%
	filter(capacity_mw_eia > 10000) %>%
	nrow

# do those rows match to EIA? what capacity does EIA have?
Pudl %>%
	select(plant_name_eia, plant_name_ferc, capacity_mw_ferc1, capacity_mw_eia, report_year) %>%
	filter(capacity_mw_ferc1 > 10000) %>%
	select(plant_name_ferc, capacity_mw_ferc1, capacity_mw_eia)

# what capacity does Uday have for these rows?
	# Note that there's some fan out if we simply join by plant_name_ferc and report_year; this comes from the RMI side
Pudl %>%
	filter(capacity_mw_ferc1 > 10000) %>%
	distinct(plant_name_ferc, report_year) %>%
	left_join(Rmi) %>%
	arrange(plant_name_ferc)


# are the capacities for these plants more sensible in other years?

TroubleInstances <-
	Pudl %>%
		filter(capacity_mw_ferc1 > 10000) %>%
		distinct(plant_name_ferc, report_year) %>%
		mutate(is_trouble_year = TRUE)

SubsetTrouble <-
	Pudl %>%
		semi_join(TroubleInstances, by = 'plant_name_ferc') %>%
		left_join(TroubleInstances, by = c('plant_name_ferc', 'report_year')) %>%
		select(plant_name_ferc, report_year, capacity_mw_ferc1, is_trouble_year) %>%
		mutate(is_trouble_year = replace_na(is_trouble_year, FALSE)) %>%
		arrange(plant_name_ferc, report_year)

SubsetTrouble %>%
	ggplot(aes(x = report_year, y = capacity_mw_ferc1)) +
	geom_point(aes(color = is_trouble_year)) +
	geom_hline(yintercept = 10000, linetype = 'dashed') +
	geom_line() +
	facet_wrap(~plant_name_ferc, scales = 'free', ncol = 2) +
	theme(
		legend.position = 'none'
	)

SubsetTrouble %>%
	write_csv('~/Downloads/subset_trouble.csv')
