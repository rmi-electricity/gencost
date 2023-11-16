library(tidyverse)
library(dplyr)
library(RSQLite)
library(skimr)

con <- DBI::dbConnect(RSQLite::SQLite(), dbname = "/Volumes/Extreme SSD/pudl.sqlite")
QueryMapping <- tbl(con, "out__yearly_plants_all_ferc1_plant_parts_eia")

QueryMapping %>%
	colnames %>%
	sort

CleanQueryMapping <-
	QueryMapping %>%
		select(
			'record_id_ferc1',
			'technology_description',
			'plant_type',
			'capacity_mw_ferc1',
			'capacity_mw_eia',
			'prime_mover_code',
			"plant_id_eia",
			"plant_name_eia",
			"plant_name_ferc" = "plant_name_ferc1",
			'report_year',
			'match_type'
		) %>%
		collect()

CleanQueryMapping %>%
	mutate(plant_id_eia = as.character(as.integer(plant_id_eia))) %>%
	filter(str_detect(record_id_ferc1, 'steam')) %>%
	select(-record_id_ferc1) %>%
	write_csv('clean_data/pudl.csv')
dbDisconnect(con)


# denorm_plants_eia
con <- DBI::dbConnect(RSQLite::SQLite(), dbname = "/Volumes/Extreme SSD/pudl.sqlite")
QueryPlants <- tbl(con, "denorm_plants_eia")
QueryPlants %>%
	colnames %>%
	sort

QueryPlants %>%
	distinct(plant_id_eia, plant_name_eia) %>%
	mutate(plant_id_eia = as.character(plant_id_eia)) %>%
	collect() %>%
	write_csv('clean_data/map_id_to_name.csv')
dbDisconnect(con)

# denorm_generators_eia
con <- DBI::dbConnect(RSQLite::SQLite(), dbname = "/Volumes/Extreme SSD/pudl.sqlite")
Table <- tbl(con, "denorm_generators_eia")
Table %>%
	colnames %>%
	sort

Table %>%
	select(capacity_mw, plant_id_eia, report_date)
dbDisconnect(con)


# plant_parts_eia
# Alex:
# I don't think plant_part_eia has a column that indicates whether it would be
# considered steam for FERC purposes. I think I would filter
# out__yearly_plants_all_ferc to steam, see what technology_description s remain
# and then select those technology descriptions from plant_part_eia

# we need steam only plants
# semi-join plant_parts_eia to these plants
# then roll up to plant_id_eia

con <- DBI::dbConnect(RSQLite::SQLite(), dbname = "/Volumes/Extreme SSD/pudl.sqlite")

# 1. get all utility_id_pudl values for steam plants
# filter to steam
# get tech descriptions

Table <- tbl(con, "out__yearly_plants_all_ferc1_plant_parts_eia")
Table %>%
	colnames %>%
	sort

# MapSteamToUtilityId <-
Query <-
	Table %>%
		select(technology_description, record_id_ferc1) %>%
		collect
dbDisconnect(con)

Onshore Wind Turbine                          169
12 Solar Photovoltaic
'Conventional Hydroelectric'

# SemiJoinMeUtilityId <-
	Query %>%
		filter(str_detect(record_id_ferc1, 'steam')) %>%
		count(technology_description) %>%
		arrange(n)
# SemiJoinMeUtilityId

# 2. get all plants' capacity
con <- DBI::dbConnect(RSQLite::SQLite(), dbname = "/Volumes/Extreme SSD/pudl.sqlite")
Table <- tbl(con, "plant_parts_eia")

AllPartsCapacity <-
	Table %>%
		select(report_year, capacity_mw, utility_id_pudl, plant_id_eia, plant_part_id_eia) %>%
		collect
dbDisconnect(con)
# 3. Subset all plants' capacity to steam
AllPartsCapacity %>%
	semi_join(SemiJoinMeUtilityId, by = 'utility_id_pudl') %>%
	group_by()



dbListTables(con)
Table <- tbl(con, "plant_parts_eia")
Table %>%
	colnames %>%
	sort

Table %>%
	select(capacity_mw, plant_id_eia, report_date)
dbDisconnect(con)
