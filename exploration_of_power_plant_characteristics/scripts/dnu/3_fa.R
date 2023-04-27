# Clustering and latent variables
# 3. Factor Analysis/Latent Variable Analysis
# Andrew Bartnof, RMI March 2023

library(conflicted)
library(psych)
library(skimr)
library(tidyverse)
conflict_prefer("map", "purrr")
conflict_prefer("map2", "purrr")
conflict_prefer("filter", "dplyr")
set.seed(1)

is_complete <- function(X){
	mean(is.na(X)) == 0
}

X <- readRDS('clean_data/scalars_read_for_modeling.RDS')
#### Factor Analysis ####

#bootstrap:
# nest
# resample
# correlation
# FA
# extract fa_values

BootstrappedParallelTest <-
	X %>%
		nest(data = everything()) %>%
		expand_grid(boot_num = seq(1, 100)) %>%
		mutate(data = map(data, sample_frac, size = 1, replace = TRUE),
					 Rho = map(data, cor, method = 'p'), # probably use a different method later
					 n = map_int(data, nrow),
					 is_rho_ok = map_lgl(Rho, is_complete)) %>%
		filter(is_rho_ok) %>%
		mutate(parallel_fit = map2(Rho, n, psych::fa.parallel, plot = F, fa = 'fa'),
					 fa_values = map(parallel_fit, 'fa.values'),
					 FaValues = map(fa_values, enframe, 'component', 'fa_value')
		) %>%
		select(boot_num, FaValues) %>%
		unnest(FaValues)

# Pause point: save/load bootstrapped FA models
saveRDS(BootstrappedParallelTest, 'clean_data/bootstrapped_parallel_test.RDS')
BootstrappedParallelTest <- readRDS('clean_data/bootstrapped_parallel_test.RDS')
#

PairwiseTTests <-
	# Perform pairwise paired t-tests on each number of components and the 
	# previous option, no p.adjustment
	pairwise.t.test(x = BootstrappedParallelTest$fa_value, 
									g = BootstrappedParallelTest$component,
									paired = T, p.adjust.method = 'none'
	) %>%
	.$'p.value' %>%
	as.data.frame %>%
	rownames_to_column('var1') %>%
	as_tibble %>%
	gather(var0, p, -var1) %>%
	mutate_at(c('var0', 'var1'), parse_integer) %>%
	filter(var0 + 1L == var1) %>%
	mutate(is_significant = p < 0.05,
				 star = if_else(is_significant, '*', NA_character_)
  )

AvgFaValues <-
	BootstrappedParallelTest %>%
		group_by(component) %>%
		summarize(avg_fa_value = mean(fa_value)) %>%
		ungroup

# Plot
BootstrappedParallelTest %>%
	ggplot(aes(x = component, y = fa_value)) +
	geom_hline(yintercept = 1, linetype = 'dashed', color = 'red') +
	geom_line(alpha = 0.1, aes(group = boot_num)) +
	geom_text(data = PairwiseTTests, aes(x = var1, y = 9, label = star),
						size = 4, color = 'blue'
	) +
	scale_x_continuous(breaks = seq(0, 1000, by = 5), 
										 minor_breaks = seq(0, 1000, by = 1)
	) +
	scale_y_continuous(minor_breaks = seq(0, 1000, by = 1)) +
	theme(
		panel.grid.major.y = element_blank(),
		panel.grid.minor.y = element_blank(),
		#panel.grid.minor.x = element_blank(),
		axis.ticks = element_blank()
	) +
	labs(x = 'Number of components', y = 'Eigenvalue', title = 'Bootstrapped scree plots',
			 subtitle = '100 resamples')


	
# Find loadings

Rho <- X %>% cor(method='s')
fa4 <- psych::fa(Rho, nfactors = 4, n.obs = nrow(X), rotate = 'promax')
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
