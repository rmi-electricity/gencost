library(tidyverse)
DataBySubplant <- read_csv('clean_data/clean_data_by_subplant.csv')

sd(DataBySubplant$gross_generation_mwh)


Gof <-
	bind_rows(
		read_csv('clean_data/gof_mean_median.csv'),
		read_csv('clean_data/gof_mean_median_by_prime_mover.csv'),
		read_csv('clean_data/gof_glm.csv')
	)

Gof %>%
	mutate(
		model = factor(model),
		model = fct_reorder(model, rmse, mean)
	) %>%
	ggplot(aes(x = model, y = rmse)) +
	geom_boxplot() +
	scale_y_continuous(
		sec.axis = sec_axis(~ ./sd(DataBySubplant$gross_generation_mwh),
												name = 'Gross gen standard deviations'
		)) +
	expand_limits(y = 0) +
	coord_flip() +
	labs(y = 'RMSE')
