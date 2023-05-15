# Clustering and latent variables
# Andrew Bartnof, RMI March 2023

# Question 1: Does a GMM clustering model jibe with how we've manually clustered the models?
# - am i excluding the right variables in data cleaning?
# - how many clusters?
# - can someone show me which are the obvious and non-obvious cases, and we can compare that to the model?

# Question 2: Factor analysis
# - am i excluding the right variables in data cleaning?
# - can we verify that the number/composition of predictor variables being used makes sense against the model?


# clustering will come first-- upon which variables? this will change the outcome here
# non-linear variables (eg month, long/lat)
# which factors can actually be binary (ie dummy-coded, or at least simplified)?
# some have no variance

# LAVAAN- what is the dv

library(tidyverse)
library(arrow)
library(skimr)
library(mclust)
library(conflicted)
conflict_prefer("map", "purrr")
set.seed(1)
#library(polycor)
#library(psych)
#library(lubridate)

##### Define custom functions #####

impute_nonfinite_values <- function(xx){
	# Replace Inf and NA values with 0.0
	is_nonfinite <- is.na(xx)|(!is.finite(xx))
	yy <- if_else(is_nonfinite, 0.0, xx)
	return(yy)
}

#### ELT ####

Data <- arrow::read_parquet('data/data_for_pf_subplants.parquet') %>% 
	as_tibble

Scalars <-
	Data %>%
		mutate_at(vars(contains('id')), as.factor) %>%
		mutate_at(vars(contains('code')), as.factor) %>%
		mutate_at(vars(contains('index')), as.factor) %>%
		mutate_at(vars(contains('date')), as.integer) %>%
		select(-latitude, -longitude) %>%
		select_if(is.numeric)

# Replace infinite with NA
Scalars[sapply(Scalars, is.infinite)] <- NA

# Center
ScalarsZ <-
	Scalars %>%
		mutate_all(~as.vector(scale(.))) %>%
		mutate_all(impute_nonfinite_values)

valid_columns <-
	ScalarsZ %>%
		map_dbl(sd) %>%
		enframe('variable', 'std') %>%
		filter(std > 0) %>%
		pull(variable)

print(str_c('# of columns removed: ', ncol(ScalarsZ) - length(valid_columns)))
setdiff(colnames(ScalarsZ), valid_columns)

ModelMe <-
	ScalarsZ %>%
		select_at(valid_columns)

#### GMM ####
# https://mclust-org.github.io/mclust/reference/mclustModelNames.html
# EEE: ellipsoidal, equal volume, shape, and orientation

bic <- mclustBIC(ModelMe)
summary(bic) %>% enframe('model', 'BIC')
#

plot(bic)
summary(bic)
mod1 <- Mclust(ModelMe, x = bic)
mod1$classification
mod1$z %>%
	as.data.frame %>%
	as_tibble

##### GMM boot ####
ModelMe %>% 
	as.data.frame %>%
	nest(data = everything()) %>%
	expand_grid(n_iter = seq(1, 2)) %>%
	mutate(data = map(data, sample_frac, size = 1, replace = T),
				 bic = map(data, mclustBIC)
	) %>%
	print
	
	


ModelMe %>%
	sample_frac(tbl = ., size = 0.5, replace = T)

ChickWeight %>%
	as_tibble %>%
	nest(data = everything()) %>%
	expand_grid(n_iter = seq(1, 2)) %>%
	mutate(data = map(data, slice))
	print
#

#### Factor Analysis ####

Rho <- ModelMe %>% cor(method='s')

# Scree plot suggests 13 factors, but i think 4 is logical
psych::fa.parallel(Rho, n.obs=nrow(ScalarsZ), fa='fa')

fa4 <- psych::fa(Rho, nfactors = 4, n.obs = nrow(ScalarsZ), rotate = 'promax')
fa4$loadings %>% 
	unclass %>%
	as.data.frame %>%
	rownames_to_column('variable') %>%
	as_tibble %>%
	gather(latent_variable, loading, -variable) %>%
	arrange(latent_variable, loading) %>%
	ggplot(aes(latent_variable, variable, fill = loading, label = round(loading, 1))) +
	geom_raster() +
	geom_text() +
	scale_fill_gradient2(limits = c(-1, 1), 
											 low = 'red',
											 mid = 'white', 
											 high = 'green') +
	scale_y_discrete(limits = rev)
