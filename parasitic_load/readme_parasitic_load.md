# Parasitic Cost Regression Model
Andrew Bartnof for RMI 2023

## Abstract
This module contains a function that, out of the box, allows any user to use a random forest regression model to predict a power plant\'s parasitic load.
Because we have already coded our desired hyper-parameters into the script, and because fitting a random forest is so computationally-cheap, this module is speedy and easy to use.

## Background
When a power plant is activated, some of the energy that it produces is lost ([Wikipedia.org](https://en.wikipedia.org/wiki/Losses\_in\_electrical\_systems\#Parasitic\_loss\)\).
Regardless of why this energy is lost (perhaps, for example, the plant loses some electrical efficiency to heat), the difference between the *gross electric yield* and the *productive yield* is termed the *parasitic load*.

In order to run our GenCost algorithm, we needed to be able to describe the parasitic load of all of the power plants in the USA.
However, we only had sufficient data to algebraically calculate the parasitic load for a fraction of these plants.
Consequently, we trained a model to predict the parasitic load of any given plant.

This Python module presents a Random Forest implementation of a regression model that can predict a plant\'s parasitic load.

## Introduction
We define *parasitic load* as:

> `(gross_generation_mwh - net_generation_mwh) / (capacity_mw * 8,760)`

\...where the denomenator seeks to normalize each plant\'s parasitic
load based on the plant\'s capacity; 8,760 represents the approximate
number of hours in a year.

We tested various regression model types, and settled on random forest.
Our reasons:
* Lower RMSE (root mean squared error) on our testing sets
than competing models
* Computationally cheap
* Easily accomodates non-gaussian variables

This module is set up so that the user doesn\'t need to worry about the random forest model per se.
There is one function in the module, called `predict_parasitic_load()`.
This function takes two arguments:
* a dataset describing plants for whom we can mathematically calculate parasitic load
* \... and a dataset listing plants for whom we cannot

Under the hood, this function is actually calling three functions:
* `check_data_by_subplant()`: This function can be called to check either the training data, or the new data for which we need fitted values. It will confirm that all of the right variables are in place, and that these variables are the desired types. This module runs this quality control step on both the training and new datasets.
* `feature_engineering()`: This function fits the feature engineering steps on the training data, and then applies them to the new data.
* `get_y_fit()`: Fits a sci-kit learn random forest model, using the hyper parameters we already selected; then, it predicts the parasitic\_load for the new data.

On my desktop, which is about three years old and not extraordinary fast, this entire set of steps takes about one second to run.

## predict\_parasitic\_load(DataBySubplants, NewData)
Arguments:
* DataBySubplant: Our Pandas table that contains all of the variables (both independent and dependent) that we'll use to train our model
* NewData: A Pandas table that contains the same independent variables as DataBySubplant, but not the dependent variables. The model will fit parasitic load values for this

Returns: NewData, with a new column appended: parasitic\_load, which is our fitted value

This function uses the training data (DataBySubplant) to train a Random Forest regression model.
It will then predict the parasitic load of the new data, append that value onto the new data set, and return new data with the fitted values.

## Discussion of model performance
As noted above, random forest had pretty low RMSE rate.
We also found some interesting findings (though, naturally, your mileage may vary):
* We only train the model on data in which parasitic load was greater than or equal to zero; consequently, we didn\'t find that the model produces any parasitic loads less than zero. Note that we don\'t artificially set a floor value for parasitic loads, so it is possible that you\'ll encounter such a fitted value!
* Our training dataset contained a few dozen plants where parasitic load exceeded one; we accepted this as a type of legal outlier, given how we defined our parasitic load metric, and we did not exclude them from the training set. We found that the model would occasionally predict parasitic loads in excess of one, and that these predictions were about the same size (generally between 1 and 8) as the training values. Again, there is no artificial ceiling set on parasitic load, so we can\'t guarantee the kinds of fitted values you\'ll find.
