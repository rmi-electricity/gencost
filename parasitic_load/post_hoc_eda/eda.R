# scenarios to explore:
	# real parasitic_load < 0
	# real parasitic_load > 1

	# fitted parasitic_load < 0
	# fitted_parasitic_load > 1

library(tidyverse)
library(skimr)

variables_to_select <- c(
	# DV:
	'parasitic_load_fit',  # note: gross_generation_mwh is now not in the model
	'parasitic_load_true',
	# IVs:
	'gross_generation_mwh', # TODO: remove from feature engineering
	'capacity_mw',
	'net_generation_mwh',
	# 'heat_in_mmbtu',
	'prime_mover',
	#'balancing_authority_code_eia',
	'state',
	#'utility_id_eia',
	'associated_combined_heat_power',
	'duct_burners',
	'bypass_heat_recovery',
	'solid_fuel_gasification',
	'carbon_capture',
	'fluidized_bed_tech',
	'pulverized_coal_tech',
	'stoker_tech',
	'other_combustion_tech',
	'subcritical_tech',
	'supercritical_tech',
	'ultrasupercritical_tech',
	'age_in_report_year',
	'age_in_current_year',
	'age_of_observation',
	'age_relative_to_prime_avg',
	'pollution_control_costs_per_kw',
	#'respondent_id',
	#'respondent_id_purchaser',
	#'final_respondent_id',
	#'final_ba_code',

	# remove out of a sense of caution:
	# 'biofuel_mmbtu',
	# 'coal_mmbtu',
	# 'natural_gas_mmbtu',
	# 'other_mmbtu',
	# 'other_gas_mmbtu',
	# 'petroleum_mmbtu',
	# 'petroleum_coke_mmbtu',
	'biofuel_net_mwh',
	'coal_net_mwh',
	'natural_gas_net_mwh',
	'other_net_mwh',
	'other_gas_net_mwh',
	'petroleum_net_mwh',
	'petroleum_coke_net_mwh'
	# New columns, which add up to capacity_mw per row
	# 'All Other',
	# 'Coal Integrated Gasification Combined Cycle',
	# 'Conventional Steam Coal',
	# 'Landfill Gas',
	# 'Municipal Solid Waste',
	# 'Natural Gas Fired Combined Cycle',
	# 'Natural Gas Fired Combustion Turbine',
	# 'Natural Gas Steam Turbine',
	# 'Other Gases',
	# 'Other Waste Biomass',
	# 'Petroleum Coke',
	# 'Petroleum Liquids',
	# 'Solar Thermal without Energy Storage',
	# 'Wood/Wood Waste Biomass'
)


Data <- read_csv('post_hoc_eda/modeled.csv') %>%
	filter(prime_mover %in% c('CC', 'GT', 'ST')) %>%
	rename(parasitic_load_fit = parasitic_load) %>%
	mutate(
		parasitic_load_true = (gross_generation_mwh - net_generation_mwh) / (capacity_mw * 8760)
	) %>%
	select(all_of(variables_to_select))

#### Parasitic load < 0
# Results <-
	Data %>%
		mutate(
			exceeds_true = parasitic_load_true < 0,
			exceeds_fit  = parasitic_load_fit < 0
		) %>%
		mutate_at(c('exceeds_true', 'exceeds_fit'), factor, levels = c(TRUE, FALSE)) %>%
		count(exceeds_true, exceeds_fit, .drop = F) %>%
		ggplot(aes(x = exceeds_fit, y = exceeds_true, label = scales::comma(n))) +
		geom_text() +
		scale_x_discrete(position = "top") +
		labs(x = 'Fitted values', y = 'True values', title = 'Confusion matrix: parasitic_load < 0') +
		theme(
			panel.background = element_blank(),
			axis.ticks = element_blank(),
			text = element_text(family = 'serif')
		)

	Data %>%
		filter(parasitic_load_true < 0) %>%
		ggplot(aes(x = parasitic_load_true)) +
		geom_histogram() +
		scale_y_continuous(labels = scales::comma_format(1)) +
		labs(x = 'True parasitic load', y = 'n', title = 'Distribution of true negative parasitic loads') +
		theme(
			text = element_text(family = 'serif'),
			axis.ticks = element_blank()
		)

	Data %>%
		mutate(
			exceeds_true = parasitic_load_true < 0,
			exceeds_fit  = parasitic_load_fit < 0
		) %>%
		mutate_at(c('exceeds_true', 'exceeds_fit'), factor, levels = c(TRUE, FALSE)) %>%
		mutate(prime_mover = factor(prime_mover, levels = c('GT', 'CC', 'ST'))) %>%
		count(prime_mover, exceeds_true, exceeds_fit, .drop = F) %>%
		ggplot(aes(x = exceeds_fit, y = exceeds_true, label = scales::comma(n))) +
		geom_text() +
		scale_x_discrete(position = "top") +
		facet_wrap(~prime_mover) +
		labs(x = 'Fitted values', y = 'True values', title = 'Confusion matrix: parasitic_load < 0') +
		theme(
			# panel.background = element_blank(),
			panel.grid = element_blank(),
			axis.ticks = element_blank(),
			text = element_text(family = 'serif')
		)

# real parasitic_load < 0

Results <-
	Data %>%
		select(-parasitic_load_fit) %>%
		mutate(my_group = if_else(parasitic_load_true < 0, 'Negative', 'Positive')) %>%
		select(-parasitic_load_true)

Results %>%
	select(-prime_mover, -state) %>%
	gather(variable, value, -my_group) %>%
	drop_na(value) %>%
	group_by(variable) %>%
	mutate(z = as.vector(scale(value))) %>%
	ungroup %>%
	group_by(my_group, variable) %>%
	summarize(z_mean = mean(z)) %>%
	ungroup %>%
	spread(my_group, z_mean) %>%
	mutate(delta = Negative - Positive) %>%
	mutate(
		variable = fct_reorder(variable, -delta),
		delta_sign = delta > 0
		) %>%
	ggplot(aes(x = variable)) +
	geom_hline(yintercept = 0, linetype = 'dashed') +
	geom_segment(aes(xend = variable, y = Positive, yend = Negative, color = delta_sign)) +
	geom_label(aes(y = Positive), label = '+') +
	geom_label(aes(y = Negative), label = '-') +
	coord_flip() +
	scale_color_manual(values = c('dodgerblue', 'darkgrey')) +
	theme(
		legend.position = 'none',
		text = element_text(family = 'serif'),
		axis.ticks = element_blank()
	) +
	labs(x = '', y = 'Standard deviations', title = 'True parasitic load')

Results %>%
	count(my_group) %>%
	ggplot(aes(x = my_group, y = n, fill = my_group)) +
	geom_col() +
	scale_fill_manual(values = c('maroon', 'darkgrey')) +
	scale_y_continuous(labels = scales::comma_format(1)) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		text = element_text(family = 'serif'),
		legend.position = 'none'
	) +
	labs(x = 'True parasitic load', y = ',')

# fitted parasitic_load < 0 DON'T EXIST


#### Parasitic load > 1 ####
Results <-
	Data %>%
		mutate(
			exceeds_true = parasitic_load_true > 1,
			exceeds_fit  = parasitic_load_fit > 1
		) %>%
		select(starts_with('exceeds'), prime_mover)

Results	%>%
	mutate_at(c(1, 2), factor, levels = c(TRUE, FALSE)) %>%
	count(exceeds_true, exceeds_fit, .drop = F) %>%
	ggplot(aes(x = exceeds_fit, y = exceeds_true, label = scales::comma(n))) +
	geom_text() +
	scale_x_discrete(position = "top") +
	labs(x = 'Fitted values', y = 'True values', title = 'Confusion matrix: parasitic_load > 1') +
	theme(
		panel.background = element_blank(),
		axis.ticks = element_blank(),
		text = element_text(family = 'serif')
	)

Results	%>%
	mutate_at(c(1, 2), factor, levels = c(TRUE, FALSE)) %>%
	mutate_at(3, factor, levels = c('GT', 'CC', 'ST')) %>%
	count(exceeds_true, exceeds_fit, prime_mover, .drop = F) %>%
	ggplot(aes(x = exceeds_fit, y = exceeds_true, label = scales::comma(n))) +
	geom_text() +
	scale_x_discrete(position = "top") +
	facet_wrap(~prime_mover) +
	labs(x = 'Fitted values', y = 'True values', title = 'Confusion matrix: parasitic_load > 1') +
	theme(
		# panel.background = element_blank(),
		panel.grid = element_blank(),
		axis.ticks = element_blank(),
		text = element_text(family = 'serif')
	)


Data %>%
	mutate(
		parasitic_load_true = if_else(parasitic_load_true > 1, parasitic_load_true, NA_real_),
		parasitic_load_fit = if_else(parasitic_load_fit > 1, parasitic_load_fit, NA_real_),
	) %>%
	select(parasitic_load_true, parasitic_load_fit) %>%
	gather(variable, value) %>%
	drop_na %>%
	ggplot(aes(x = value)) +
	geom_histogram() +
	facet_wrap(~variable, ncol = 1) +
	scale_x_continuous(limits = c(0, 10), breaks = seq(0, 10, by = 2)) +
	theme(
		axis.ticks = element_blank(),
		text = element_text(family = 'serif')
	) +
	labs(x = '', y = 'n', title = 'Distribution of all parasitic load values > 1')


# Real parasitic load > 1
Results <-
	Data %>%
		select(-parasitic_load_fit) %>%
		mutate(my_group = if_else(parasitic_load_true > 1, '> 1', '<= 1')) %>%
		select(-parasitic_load_true)

Results %>%
	select(-prime_mover, -state) %>%
	gather(variable, value, -my_group) %>%
	drop_na(value) %>%
	group_by(variable) %>%
	mutate(z = as.vector(scale(value))) %>%
	ungroup %>%
	group_by(my_group, variable) %>%
	summarize(z_mean = mean(z)) %>%
	ungroup %>%
	spread(my_group, z_mean) %>%
	mutate(
		delta = `<= 1` - `> 1`,
		variable = fct_reorder(variable, -delta),
		delta_sign = delta > 0
		) %>%
	ggplot(aes(x = variable)) +
	geom_hline(yintercept = 0, linetype = 'dashed') +
	geom_segment(aes(xend = variable, y = `<= 1`, yend = `> 1`, color = delta_sign)) +
	geom_label(aes(y = `<= 1`), label = '<= 1') +
	geom_label(aes(y = `> 1`), label = '> 1') +
	coord_flip() +
	scale_color_manual(values = c('dodgerblue', 'darkgrey')) +
	theme(
		legend.position = 'none',
		text = element_text(family = 'serif'),
		axis.ticks = element_blank()
	) +
	labs(x = '', y = 'Standard deviations', title = 'True parasitic load')

Results %>%
	count(prime_mover, my_group) %>%
	group_by(prime_mover) %>%
	mutate(prop = n / sum(n)) %>%
	ungroup %>%
	ggplot(aes(x = my_group, y = prime_mover, fill = prop)) +
	geom_raster() +
	geom_text(aes(label = scales::percent(prop, 2)), family = 'serif') +
	scale_fill_gradient(low = 'white', high = 'blue', limits = c(0, 1)) +
	theme(
		axis.ticks = element_blank(),
		panel.background = element_blank(),
		text = element_text(family = 'serif'),
		legend.position = 'none'
	) +
	labs(x = 'True parasitic load', y = '')

Results %>%
	count(my_group) %>%
	ggplot(aes(x = my_group, y = n, fill = my_group)) +
	geom_col() +
	scale_fill_manual(values = c('maroon', 'darkgrey')) +
	scale_y_continuous(labels = scales::comma_format(1)) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		text = element_text(family = 'serif'),
		legend.position = 'none'
	) +
	labs(x = 'True parasitic load', y = ',')

Results %>%
	count(my_group)


# Fitted parasitic load > 1
Results <-
	Data %>%
		select(-parasitic_load_true) %>%
		mutate(my_group = if_else(parasitic_load_fit > 1, '> 1', '<= 1')) %>%
		select(-parasitic_load_fit)

Results %>%
	select(-prime_mover, -state) %>%
	gather(variable, value, -my_group) %>%
	drop_na(value) %>%
	group_by(variable) %>%
	mutate(z = as.vector(scale(value))) %>%
	ungroup %>%
	group_by(my_group, variable) %>%
	summarize(z_mean = mean(z)) %>%
	ungroup %>%
	spread(my_group, z_mean) %>%
	mutate(
		delta = `<= 1` - `> 1`,
		variable = fct_reorder(variable, -delta),
		delta_sign = delta > 0
		) %>%
	ggplot(aes(x = variable)) +
	geom_hline(yintercept = 0, linetype = 'dashed') +
	geom_segment(aes(xend = variable, y = `<= 1`, yend = `> 1`, color = delta_sign)) +
	geom_label(aes(y = `<= 1`), label = '<= 1') +
	geom_label(aes(y = `> 1`), label = '> 1') +
	coord_flip() +
	scale_color_manual(values = c('dodgerblue', 'darkgrey')) +
	theme(
		legend.position = 'none',
		text = element_text(family = 'serif'),
		axis.ticks = element_blank()
	) +
	labs(x = '', y = 'Standard deviations', title = 'Fitted parasitic load')

Results %>%
	count(prime_mover, my_group) %>%
	group_by(prime_mover) %>%
	mutate(prop = n / sum(n)) %>%
	ungroup %>%
	ggplot(aes(x = my_group, y = prime_mover, fill = prop)) +
	geom_raster() +
	geom_text(aes(label = scales::percent(prop, 2)), family = 'serif') +
	scale_fill_gradient(low = 'white', high = 'blue', limits = c(0, 1)) +
	theme(
		axis.ticks = element_blank(),
		panel.background = element_blank(),
		text = element_text(family = 'serif'),
		legend.position = 'none'
	) +
	labs(x = 'Fitted parasitic load', y = '')

Results %>%
	count(my_group) %>%
	ggplot(aes(x = my_group, y = n, fill = my_group)) +
	geom_col() +
	scale_fill_manual(values = c('maroon', 'darkgrey')) +
	scale_y_continuous(labels = scales::comma_format(1)) +
	theme(
		axis.ticks = element_blank(),
		panel.grid.major.x = element_blank(),
		text = element_text(family = 'serif'),
		legend.position = 'none'
	) +
	labs(x = 'Fitted parasitic load', y = ',')

Results %>%
	count(my_group)
