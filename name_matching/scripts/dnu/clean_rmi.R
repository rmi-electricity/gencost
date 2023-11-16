library(tidyverse)
library(skimr)
library(readxl)

RMI <- read_excel('input_data/FERC-EIA associations 860_FERC_Matching.xlsx')

RMI %>%
	select(plant_name, Plant, report_year) %>%
	rename(plant_name_ferc = plant_name, plant_id_eia = Plant) %>%
	write_csv('clean_data/rmi.csv')
