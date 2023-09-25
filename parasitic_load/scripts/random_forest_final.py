#!/usr/bin/env python3
"""
Fit final Random Forest regressor: 1 estimator, max_depth = 250
- load X_train, y_train, X_test
- fit model
- predict X_test
- save fit values to disk
Andrew Bartnof, for RMI
2023
"""

import os

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor

os.chdir("/Users/andrewbartnof/Documents/rmi/gencost/parasitic_load/")
# os.chdir('/home/rmicfequant/parasitic_load/')

# Note where the training and testing datasets are
train_x_list = [f"clean_data_py/train/train_x_{i}.npy" for i in range(1, 6)]
train_y_list = [f"clean_data_py/train/train_y_{i}.npy" for i in range(1, 6)]

test_x_list = [f"clean_data_py/test/test_x_{i}.npy" for i in range(1, 6)]
test_y_list = [f"clean_data_py/test/test_y_{i}.npy" for i in range(1, 6)]

fn_out_list = [
    f"~/Downloads/random_forest_final_num_estimators_1_x_max_depth_250_x_fold_num_{i}.csv"
    for i in range(1, 6)
]

FnTable = pd.DataFrame(
    {
        "fold_num": list(range(1, 6)),
        "train_x": train_x_list,
        "train_y": train_y_list,
        "test_x": test_x_list,
        "test_y": test_y_list,
        "fn_out": fn_out_list,
    }
)

# Test models
for i in range(FnTable.shape[0]):
    XTrain = np.load(FnTable["train_x"].values[i])
    y_train = np.load(FnTable["train_y"].values[i])

    XTest = np.load(FnTable["test_x"].values[i])
    y_test = np.load(FnTable["test_y"].values[i])

    f = FnTable["fold_num"].values[i]
    fn_out = FnTable["fn_out"].values[i]

    print(i, "/", FnTable.shape[0])

    reg = RandomForestRegressor(n_estimators=1, max_depth=250)
    reg.fit(X=XTrain, y=y_train)
    y_fit = reg.predict(XTest)

    Output = pd.DataFrame(
        columns=["y_fit", "y_true", "model", "fold_num", "num_estimators", "max_depth"]
    )
    Output["y_true"] = np.ndarray.flatten(y_test)
    Output["y_fit"] = np.ndarray.flatten(y_fit)
    Output["model"] = "Random Forest"
    Output["fold_num"] = f
    Output["num_estimators"] = 1
    Output["max_depth"] = 250
    Output.to_csv(fn_out)
exit()
