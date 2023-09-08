# parasitic load by technology descriptions

library(tidyverse)
library(skimr)
library(arrow)

DataBySubplant <- read_parquet('input_data/subplant_w_tech_by_capacity.parquet') %>%
	rowid_to_column %>%
	mutate(
		parasitic_load = (gross_generation_mwh - net_generation_mwh) / (capacity_mw * 8760)
	)

technology_columns <- c(
	'All Other',
	'Coal Integrated Gasification Combined Cycle',
	'Conventional Steam Coal',
	'Landfill Gas',
	'Municipal Solid Waste',
	'Natural Gas Fired Combined Cycle',
	'Natural Gas Fired Combustion Turbine',
	'Natural Gas Steam Turbine',
	'Other Gases',
	'Other Waste Biomass',
	'Petroleum Coke',
	'Petroleum Liquids',
	'Solar Thermal without Energy Storage',
	'Wood/Wood Waste Biomass'
)

RowidToTechTypeComplex <-
	DataBySubplant %>%
		select(all_of(technology_columns)) %>%
		mutate_all(~!is.na(.)) %>%
		bind_cols(
			DataBySubplant %>% select(rowid)
		) %>%
		gather(tech_type, value, -rowid) %>%
		filter(value) %>%
		select(rowid, tech_type) %>%
		arrange(rowid, tech_type) %>%
		group_by(rowid) %>%
		nest %>%
		mutate(
			tech_type_complex = map(data, 'tech_type'),
			tech_type_complex = map_chr(tech_type_complex, paste, collapse = '_x_')
		) %>%
		select(rowid, tech_type_complex) %>%
		ungroup

TechTypeComplexToParasiticLoad <-
	DataBySubplant %>%
		select(rowid, parasitic_load) %>%
		inner_join(RowidToTechTypeComplex, by = 'rowid')  # some rows don't have tech type


DataBySubplant %>%
	select(prime_mover, parasitic_load) %>%
	filter(prime_mover != 'IC') %>%
	mutate(is_parasitic_load_negative = parasitic_load < 0) %>%
	count(is_parasitic_load_negative)

	ggplot(aes(x = prime_mover, y = parasitic_load)) +
	geom_boxplot(outlier.color = 'dodgerblue', outlier.alpha = 0.1) +
	coord_flip()


DataBySubplant %>%
	select(rowid, parasitic_load) %>%
	left_join(RowidToTechTypeComplex, by = 'rowid') %>%  # some rows don't have tech type
	skim


TechTypeComplexToParasiticLoad %>%
	mutate(tech_type_complex = fct_reorder(tech_type_complex, parasitic_load)) %>%
	ggplot(aes(x = tech_type_complex, y = parasitic_load)) +
	geom_hline(yintercept = 0, color = 'white', size = 1.5) +
	geom_boxplot(outlier.alpha = 0.2, outlier.colour = 'dodgerblue') +
	coord_flip() +
	theme(
		axis.ticks = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = '', y = 'Parasitic load')

TechTypeComplexToParasiticLoad %>%
	count(tech_type_complex) %>%
	mutate(tech_type_complex = fct_reorder(tech_type_complex, n)) %>%
	ggplot(aes(x = tech_type_complex, y = n)) +
	geom_col() +
	coord_flip() +
	theme(
		axis.ticks = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = '', y = 'n')
