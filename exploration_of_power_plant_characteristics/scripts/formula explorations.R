
# 1. find all legal variables (ones with variance)
# 2. find minimal set (necessary variables)
# remove all illegal_cols (real_opex)
# from remaining candidate cols (all variables - necessary - illegal), find all 
	# find all permutations with 0 added to full remainders
# 4. fit training models
# 5. fit test models
get_variables_with_variance <- function(X){
	sapply(X, var) %>%
		enframe('variable', 'variance') %>%
		filter(!is.na(variance), variance > 0) %>%
		pull(variable)
}


X <-
	CleanedDataBySubplant %>%
		filter(prime_mover == 'CC') %>%
		select_if(is.numeric)

all_cols <- get_variables_with_variance(X)
necessary_cols <- c('age_variable_adj', 'CHP_variable_adj')
illegal_cols <- 'real_opex'
candidate_cols <- setdiff(all_cols, c(necessary_cols, illegal_cols))

candidate_cols

seq_along(candidate_cols) %>%
	enframe(name = NULL, value = 'num_candidate_cols')
	
# map(1:length(candidate_cols), 
Combinations <-
	map(1:length(candidate_cols), 
			~enframe(combn(candidate_cols, ., simplify = F))
	) %>%
	bind_rows
	


	
	
	
