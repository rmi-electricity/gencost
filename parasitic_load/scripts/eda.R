# EDA

library(tidyverse)
# library(skimr)

set.seed(1)
DataBySubplant <- read_csv('clean_data/clean_data_by_subplant.csv')
NestedDataBySubplant <- readRDS('clean_data/nested_data_by_subplant.RDS')

DataBySubplant %>%
	pull(gross_generation_mwh) %>%
	summary

DataBySubplant %>%
	select(gross_generation_mwh) %>%
	ggplot(aes(x = gross_generation_mwh)) +
	geom_histogram()

DataBySubplant %>%
	select(prime_mover, gross_generation_mwh) %>%
	ggplot(aes(x = gross_generation_mwh)) +
	geom_histogram() +
	facet_wrap(~prime_mover, ncol = 1, scales = 'free_y')
