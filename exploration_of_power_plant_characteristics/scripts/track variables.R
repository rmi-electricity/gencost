library(CodeDepends)
rs <- readScript(doc = '~/Documents/rmi/code/patio-model/r_src/Patio Model Fossil Cost Analysis.R')
gi <- getInputs(rs)

target <- 'python_inputs_data_hist'
fn <- str_c('~/Downloads/track_', target, sep = '')

gdt <- getDependsThread(target, gi)
results <- gi[gdt]
out <- capture.output(results)
cat(out, file = fn,sep="\n",append=TRUE)