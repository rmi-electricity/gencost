#!/usr/bin/env python3
"""
Fit SVM Polynomial models with all 5 folds on top 10 contender models:
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

# Note where the training and testing datasets are
train_x_list = [f"clean_data_py/train/train_x_{i}.npy" for i in range(1, 6)]
train_y_list = [f"clean_data_py/train/train_y_{i}.npy" for i in range(1, 6)]

test_x_list = [f"clean_data_py/test/test_x_{i}.npy" for i in range(1, 6)]
test_y_list = [f"clean_data_py/test/test_y_{i}.npy" for i in range(1, 6)]

FnIn = pd.DataFrame(
    {
        "fold_num": list(range(1, 6)),
        "train_x": train_x_list,
        "train_y": train_y_list,
        "test_x": test_x_list,
        "test_y": test_y_list,
    }
)

# Attach hyperparameters to be tested
cost_list = sorted([771, 770, 775, 769, 768, 767, 776, 772, 773, 774])
Costs = pd.DataFrame(cost_list, columns=["cost"])
Params = FnIn.merge(Costs, how="cross")

# Create fn for output file (fn_out)
fn_out_list = []
for i in range(Params.shape[0]):
    f = Params["fold_num"].values[i]
    c = Params["cost"].values[i]
    fn_out = f"svm_poly_x_degree_3_x_fold_{f}_x_cost_{c}.csv"
    fn_out_list.append(fn_out)

Params["fn_out"] = fn_out_list

# Test models
for i in range(Params.shape[0]):
    XTrain = np.load(Params["train_x"].values[i])
    y_train = np.load(Params["train_y"].values[i])

    XTest = np.load(Params["test_x"].values[i])
    y_test = np.load(Params["test_y"].values[i])

    c = Params["cost"].values[i]
    f = Params["fold_num"].values[i]
    fn_out = Params["fn_out"].values[i]

    print(i, "/", Params.shape[0])

    reg = SVR(kernel="poly", degree=3, C=c)
    reg.fit(X=XTrain, y=y_train)
    y_fit = reg.predict(XTest)

    Output = pd.DataFrame(
        columns=["y_fit", "y_true", "kernel", "fold_num", "power", "cost"]
    )
    Output["y_true"] = np.ndarray.flatten(y_test)
    Output["y_fit"] = np.ndarray.flatten(y_fit)
    Output["kernel"] = "poly"
    Output["power"] = 3
    Output["fold_num"] = f
    Output["cost"] = c
    Output.to_csv(fn_out)
exit()
