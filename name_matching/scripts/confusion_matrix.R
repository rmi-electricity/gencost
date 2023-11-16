library(tidyverse)
library(skimr)

QcRaw <- read_csv('clean_data/sample_for_qc_complete.csv')

Qc <-
	QcRaw %>%
		mutate(
			results_rmi =
			 	case_when(
			 		is_rmi_right == '1' ~ 'Correct',
			 		is_rmi_right == '0' ~ 'Incorrect',
			 		is_rmi_right == 'm' ~ 'Maybe',
			 		is.na(plant_id_eia_rmi) ~ '(Missing)',
			 		is.na(plant_name_eia_rmi) ~ '(Missing)',
			 		T ~ 'DEFAULT_UNKNOWN'
			 	),
			results_pudl =
			 	case_when(
			 		is_pudl_right == '1' ~ 'Correct',
			 		is_pudl_right == '0' ~ 'Incorrect',
			 		is_pudl_right == 'm' ~ 'Maybe',
			 		is.na(plant_id_eia_pudl) ~ '(Missing)',
			 		is.na(plant_name_eia_pudl) ~ '(Missing)',
			 		T ~ 'DEFAULT_UNKNOWN'
			 	),
			results_rmi = ordered(results_rmi, c('Correct', 'Incorrect', 'Maybe', '(Missing)', 'DEFAULT_UNKNOWN')),
			results_pudl = ordered(results_pudl, c('Correct', 'Incorrect', 'Maybe', '(Missing)', 'DEFAULT_UNKNOWN')),
		)

Qc %>%
	filter(results_rmi == 'DEFAULT_UNKNOWN' | results_pudl == 'DEFAULT_UNKNOWN')

Qc %>%
	count(results_rmi, results_pudl, .drop = F) %>%
	filter(
		results_rmi != 'DEFAULT_UNKNOWN',
		results_pudl != 'DEFAULT_UNKNOWN'
	) %>%
	rename(RMI = results_rmi, PUDL = results_pudl) %>%
	ggplot(aes(x = PUDL, y = RMI, label = scales::comma(n))) +
	geom_raster(fill = 'white') +
	geom_text() +
	scale_y_discrete(limits = rev) +
	scale_x_discrete(position = 'top')
