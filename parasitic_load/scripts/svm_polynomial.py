#!/usr/bin/env python3
"""
Fit SVM Polynomial models:
- load X_train, y_train, X_test
- establish parameters to be tested
- fit model
- predict X_test
- save fit values to disk
Andrew Bartnof, for RMI
2023
"""

import os

import numpy as np
import pandas as pd
from sklearn.svm import SVR

os.chdir("/Users/andrewbartnof/Documents/rmi/gencost/parasitic_load/")
# os.chdir('/home/rmicfequant/parasitic_load/')

# Read data
XTrain = np.load("clean_data_py/train/train_x_1.npy")
y_train = np.load("clean_data_py/train/train_y_1.npy")

XTest = np.load("clean_data_py/test/test_x_1.npy")
y_test = np.load("clean_data_py/test/test_y_1.npy")

# Establish parameters
# cost = 10.0**np.arange(-3, 4)
cost = np.arange(0, 1001)
Cost = pd.DataFrame(cost, columns=["cost"])
power = [2, 3]
Power = pd.DataFrame(power, columns=["power"])

Params = Cost.merge(Power, how="cross")
nrow = Params.shape[0]
fn_list = []
for i in range(nrow):
    p = Params["power"].values[i]
    c = Params["cost"].values[i]
    fn = "kernel_poly" + "_x_power_" + str(p) + "_x_cost_" + str(c) + ".csv"
    fn_list.append(fn)
Params["fn"] = fn_list

# Fit model
for i in range(nrow):
    print(i, "/", nrow)
    p = Params["power"].values[i]
    c = Params["cost"].values[i]
    fn = Params["fn"].values[i]
    reg = SVR(kernel="poly", degree=p, C=c)
    reg.fit(X=XTrain, y=y_train)
    y_fit = reg.predict(XTest)

    Output = pd.DataFrame(columns=["y_fit", "y_true", "kernel", "power", "cost"])
    Output["y_true"] = np.ndarray.flatten(y_test)
    Output["y_fit"] = np.ndarray.flatten(y_fit)
    Output["kernel"] = "poly"
    Output["power"] = p
    Output["cost"] = c
    Output.to_csv(fn)
exit()
