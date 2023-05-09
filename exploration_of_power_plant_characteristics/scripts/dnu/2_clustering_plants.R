# Clustering and latent variables
# 2. Clustering Plants
# Andrew Bartnof, RMI March 2023
# note: find the largest BIC values for goodness of fit testing in mclust
# https://stats.stackexchange.com/questions/237220/mclust-model-selection#239459

library(fastDummies)
library(conflicted)
library(mclust)
library(skimr)
library(tidyverse)
conflict_prefer("map", "purrr")
conflict_prefer("map2", "purrr")
conflict_prefer("filter", "dplyr")
set.seed(1)
setwd('Documents/rmi/power_plant_characteristics/')

RawData <- read_rds('clean_data/RawData.RDS')
Data <- read_rds('clean_data/Data.RDS')
#### Prime mover as category: how many observations per group? ####
RawData %>%
	distinct(prime_mover, plant_name_eia) %>%
	count(prime_mover, name = 'num_plants')

#### GMM for clustering ####
# if we use the dummy_cols function, mclustBIC doesn't work- likely too washed out by too many variables
ScaledData <-
	Data %>%
		select(-report_date) %>%
		select_if(is.numeric) %>%
		mutate_all(~as.vector(scale(.))) %>%
		mutate_all(replace_na, 0)

scale_and_impute <- function(X){
	ScaledX <-
		X %>% 
			mutate_all(scale) %>%
			mutate_all(as.vector) %>%
			mutate_all(replace_na, 0)
	return(ScaledX)
}
	
BootstrappedMods <-
	Data %>%
		select_if(is.numeric) %>%
		nest(data = everything()) %>%
		expand_grid(boot_num = seq(1, 10), 
								num_clusters = seq(2, 15)
		) %>%
		mutate(data = map(data, sample_frac, size = 1, replace = T),
					 data = map(data, scale_and_impute),
					 mod = map2(data, num_clusters, ~Mclust(data = .x, G = .y))
		)
#
saveRDS(object = BootstrappedMods, 
				file = 'clean_data/bootstrapped_cluster_results.RDS'
)
BootstrappedMods = readRDS(file = 'clean_data/bootstrapped_cluster_results.RDS')

# Note each resample's best-fitting number of components; then, count this
# to find the number of components that seems to fit best

BootstrappedBic <-
	BootstrappedMods %>%
		mutate(BIC = map(mod, 'BIC'),
					 BIC = map(BIC, summary),
					 BIC = map(BIC, unclass),
					 BIC = map(BIC, enframe, name = 'model_name', value = 'bic')) %>%
		select(boot_num, num_clusters, BIC) %>%
		unnest(BIC) %>%
		separate(model_name, c('shape', NULL), remove = T, sep = ',')

# Find the first number of components that is statistically better than it's 
# predecessor
PVals <-
	pairwise.t.test(x = BootstrappedBic$bic, 
									g = BootstrappedBic$num_clusters, 
									p.adjust.method = 'none',
									paired = TRUE) %>%
		.$p.value %>%
		as.data.frame %>%
		rownames_to_column('var1') %>%
		as_tibble %>%
		gather(var0, p, -var1) %>%
		drop_na %>%
		mutate_at(c('var1', 'var0'), parse_integer) %>%
		filter(var1 - 1L == var0) %>%
		mutate(is_sig = p < 0.05,
					 sig_label = if_else(is_sig, '*', NA_character_),
					 num_clusters = as.integer(var1)
		)

BootstrappedBic %>%
	ggplot(aes(x = num_clusters, y = bic)) +
	geom_boxplot(aes(group = num_clusters)) +
	geom_text(data = PVals, y = 1000000, aes(label = sig_label), size = 5) +
	expand_limits(y = 1000000) +
	scale_x_continuous(minor_breaks = seq(1, 20)) +
	scale_y_continuous(labels = scales::comma_format()) +
	labs(x = 'Number of clusters', y = 'BIC') +
	theme(axis.ticks = element_blank(),
				panel.grid.minor.y = element_blank())


mod12 <-
	Data %>%
		select_if(is.numeric) %>%
		scale_and_impute %>%
		Mclust(G = 12)

Cls <-
	data.frame(
		cls12 = mod12$classification,
		prime_mover = Data$prime_mover) %>%
	as_tibble

Cls %>%
	mutate_at('cls12', str_pad, width = 2, side = 'left', pad = '0') %>%
	gather(variable, value) %>%
	count(variable, value) %>%
	ggplot(aes(x = value, y = n)) +
	geom_col() +
	scale_y_continuous(labels = scales::comma_format()) +
	facet_wrap(~variable, scales = 'free_x') +
	labs(x = 'Cluster', y = 'n', title = 'Frequency of each cluster') +
	theme(axis.ticks = element_blank(),
				panel.grid.major.x = element_blank()
	) +
	expand_limits(y = 3000)
#
Cls %>%
	mutate_all(as.factor) %>%
	count(cls12, prime_mover, .drop = T) %>%
	mutate(n_bin = cut_width(n, width = 150, boundary = 0)) %>%
	ggplot(aes(x = prime_mover, y = cls12, label = n, fill = n_bin)) +
	geom_raster() +
	scale_fill_brewer(palette="YlOrRd") +
	theme_minimal() +
	theme(panel.grid.major.y = element_blank(),
		legend.position="bottom"
	) +
	scale_x_discrete(position = 'top') +
	scale_y_discrete(limits = rev) +
	labs(x = '', y = '', title = 'Frequency of overlapping categorizations',
			 fill = 'n')

RawData %>%
	select(plant_name_eia, plant_id_eia) %>%
	bind_cols(Cls) %>%
	distinct(plant_id_eia, cls12) %>%
	count(plant_id_eia)  %>%
	pull(n) %>%
	skim

RawData$real_opex_per_kw %>%
	skim
