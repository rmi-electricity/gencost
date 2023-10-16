# GENCOST CLUSTERING AND REGRESSIONS
Andrew Bartnof, 2023
For RMI

This suite of scripts allows us to predict the:
* variable operations and maintenance
* fixed operations and maintenance
* start-up operations and maintenance costs
for any powerplant.

These scripts are intended to be run in sequence: in general, each script picks up where the last one left off.

## Data that you'll need

## 0. setup.R
This script will attempt to install, and load, each of the libraries that the pipeline depends on:
* arrow
* broom
* conflicted
* flexclust
* gtools
* psych
* skimr
* tidyverse
If you already have these libraries installed, then this script is unnecessary for you.

## 1. Initial Transformations
Documents needed:
* DataBySubplant: A table that contains both the dependent and independent variables for the model, i.e. a complete dataset. This will be used to train our models
* NewData: A table that only contains the independent variables for the model, i.e. an incomplete dataset. The models will fit values for these data
* LongVariableKey: A table that lists the qualities of each variable used (which prime mover it's useful for; whether we consider it a necessary or optional variable for our analytics, etc.)

Documents produced:
* CleanedDataBySubplant: DataBySubplant, with minimal filtering and transformations
* CleanedNewData: NewData, with minimal filtering and transformations

This script takes care of two crucial munging steps: data cleaning, and (minimal) data transformation.
The data cleaning is mostly filtering out outliers.
The data transformation is all arithmatic (combining several columns to create a new one).

### 2. module_pca.R
Documents needed:
* CleanedDataBySubplant: A version of DataBySubplant that's sufficiently munged for the proceeding steps; produced in the previous step.
* CleanedNewData: A version of NewData that's sufficiently munged for the proceeding steps; produced in the previous step.
* LongVariableKey: A table that lists the qualities of each variable used (which prime mover it's useful for; whether we consider it a necessary or optional variable for our analytics, etc.)

Documents produced:
* WeightedDataBySubplantScores: PCA scores representing the original data, but with the colinearity in the data reduced. Each component's score is then weighted by how much
* WeightedNewDataScores: PCA scores representing the new data, but with the colinearity in the data reduced. Each component's score is then weighted by how much

Initially, we tried to break our DataBySubplant data directly into clusters, but we ran into an issue: many of the variables that were relevant to us were highly colinear.
This was, in some cases, because they were measuring exogenous phenomena that were highly correlated; in other cases, this was because we were creating novel variables that correlated highly with each other.

A PCA analysis was performed in order to represent our highly colinear dataset in a way that captured all of the relevant information, without the problematic redundancy.
We would then scale each component’s score, and multiply (ie weight) this score by the total percentage of variance that this component explained.
(This step would ensure that the subsequent clustering step would properly weight each component, by importance.)

### 3. clusters.R
Documents needed:
* WeightedDataBySubplantScores: PCA scores representing the original data, but with the colinearity in the data reduced. Each component's score is then weighted by how much
* WeightedNewDataScores: PCA scores representing the new data, but with the colinearity in the data reduced. Each component's score is then weighted by how much
* DataBySubplant: A table that contains both the dependent and independent variables for the model, i.e. a complete dataset. This will be used to train our models

Documents produced:
* ClustersFit: an RDS file which stores the clusters, and assigns a cluster to each row in the DataBySubplant table
* ClusteredNewData: an RDS file which assigns a cluster to each row in the NewData table

By clustering the plants, we're able to group them into relatively sensible groups that will each share a linear regression model in the subsequent script.
We settled on 3 clusters for ST and GT plants, respectively, and 4 for STs.
We fitted the entire DataBySubplant dataset to these parameters, and then assigned each row of the incomplete dataset to these clusters.

We have hard-coded the number of clusters that we want into the script, but instead of saving the clustering model to your disk, we allow the clustering model to run anew each time you use this script; this is our compromise between wanting to be flexible enough to allow for new rows in the DataBySubplant data, and maintaining a relatively consistent way of divvying up the plants.

### 4. regressions.R
Documents needed:
* ClustersFit: an RDS file which stores the clusters, and assigns a cluster to each row in the DataBySubplant table
* CleanedDataBySubplant: DataBySubplant, with minimal filtering and transformations
* CleanedNewData: NewData, with minimal filtering and transformations
* LongVariableKey: A table that lists the qualities of each variable used (which prime mover it's useful for; whether we consider it a necessary or optional variable for our analytics, etc.)

Documents produced:
* ChosenCoefficients: A table with all of the coefficients chosen for our formulas
* ChosenFormulas: A table with each of the formulas chosen
* MeanRMSE: A table that lists the mean RMSE for each of the formulas, aggregated across folds

Ultimately we'll want one linear regression formula for each cluster of plants.
We know which variables are necessary, and which should not be used.
So, for each prime_mover, for each cluster, we iterate through all possible models that contain all necessary variables, and may contain any number of optional variables, to find the formula with the best fit.
Note that we use training and testing sets to ensure we don't overfit on the data.
*This script is a bit computationally-expensive, because of how many models it compares.*

## 5. final transformations
Documents needed:
* DataBySubplant: A table that contains both the dependent and independent variables for the model, i.e. a complete dataset. This will be used to train our models
* NewData: A table that only contains the independent variables for the model, i.e. an incomplete dataset. The models will fit values for these data
* CleanedDataBySubplant: DataBySubplant, with minimal filtering and transformations
* CleanedNewData: NewData, with minimal filtering and transformations
* ChosenCoefficients: A table with all of the coefficients chosen for our formulas
* ChosenFormulas: A table with each of the formulas chosen
* ClustersFit: an RDS file which stores the clusters, and assigns a cluster to each row in the DataBySubplant table
* ClusteredNewData: an RDS file which assigns a cluster to each row in the NewData table

Documents produced:
* ResultsNewData: This is the NewData set-- as it stood at the beginning of the workflow-- with four new columns appended: fom (fixed), vom (variable), som (start-up), and om_per_mwh

Combine the clustered data with the modelled coefficients in order to          calculate our outcome variables, modelling power plant costs
