# Simple model: overall mean and median

library(tidyverse)
library(Metrics)

set.seed(1)
# DataBySubplant <- read_csv('clean_data/clean_data_by_subplant.csv')
NestedDataBySubplant <- readRDS('clean_data/nested_data_by_subplant.RDS')

# formula is taken from the waterfall.py script
glm_formula <- 'gross_generation_mwh ~ prime_mover + net_generation_mwh + capacity_mw + age_of_observation + age_in_report_year'

GofGlm <-
	NestedDataBySubplant %>%
		bind_cols(glm_formula = glm_formula) %>%
		mutate(
			glm_fit = map2(train, glm_formula,
										 ~glm(data = .x, formula = .y, family = 'poisson')),
			y_fit = map2(glm_fit, test, predict.glm),
			y = map(test, 'gross_generation_mwh')
		) %>%
		select(fold_num, y_fit, y) %>%
		unnest(c(y_fit, y)) %>%
		group_by(fold_num) %>%
		summarize(rmse = Metrics::rmse(y_fit, y)) %>%
		ungroup %>%
		mutate(model = 'Generalized linear model')

write_csv(GofGlm, 'clean_data/gof_glm.csv')

# Diagnostics #
# glm_fit <- glm(data = DataBySubplant, formula = glm_formula, family = 'poisson')
# summary(glm_fit)
