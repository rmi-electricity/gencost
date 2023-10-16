# GenCost workflow
# 0. Initial Transformations
# Andrew Bartnof, for RMI, 2023
# abartnof.contractor@rmi.org
# Ensure that the user has all of the necessary packages
# installed for the following scripts

# In order to run the following scripts, you'll need these libraries.
install.packages('arrow')
install.packages('broom')
install.packages('conflicted')
install.packages('flexclust')
install.packages('gtools')
install.packages('psych')
install.packages('skimr')
install.packages('tidyverse')

# You can verify that you have each one of them by trying to load them here.
library(arrow)
library(broom)
library(conflicted)
library(flexclust)
library(gtools)
library(psych)
library(skimr)
library(tidyverse)
