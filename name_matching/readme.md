To recreate the data pull from the Pudl data, download this:
https://s3.us-west-2.amazonaws.com/pudl.catalyst.coop/dev/pudl.sqlite

and do this:


`
library(tidyverse)
library(dplyr)
library(RSQLite)

con <- DBI::dbConnect(RSQLite::SQLite(), dbname = "/Volumes/Extreme SSD/pudl.sqlite")
Pudl <- tbl(con, "out__yearly_plants_all_ferc1_plant_parts_eia")
Pudl %>%
	select(
		"plant_id_eia",
		"plant_id_ferc1",
		"plant_id_pudl",
		"plant_name_eia",
		"plant_name_ferc1",
		"plant_name_ppe",
		"plant_part",
		"plant_part_id_eia",
		"plant_type"
	) %>%
	collect() %>%
	write_csv('input_data/pudl.csv')`
