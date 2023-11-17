# GenCost workflow
# 0: Module Setup
# Andrew Bartnof, for RMI, 2023
# abartnof.contractor@rmi.org

# Ensure necessary packages are installed

if(!require(tidyverse)){
	install.packages("tidyverse")
}
if(!require(arrow)){
	install.packages("arrow")
}
if(!require(broom)){
	install.packages("broom")
}
if(!require(conflicted)){
	install.packages("conflicted")
}
if(!require(flexflust)){
	install.packages("flexclust")
}
if(!require(psych)){
	install.packages("psych")
}
if(!require(skimr)){
	install.packages("skimr")
}
