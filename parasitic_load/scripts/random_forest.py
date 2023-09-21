#!/usr/bin/env python3
"""
Fit random forest models
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
from sklearn.ensemble import RandomForestRegressor

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
num_estimators = list(range(1, 500))
NumEstimators = pd.DataFrame(num_estimators, columns=["num_estimators"])
max_depth = list(range(1, 500))
MaxDepth = pd.DataFrame(max_depth, columns=["max_depth"])
Params = FnIn.merge(NumEstimators, how="cross").merge(MaxDepth, how="cross")

# Create fn for output file (fn_out)
fn_out_list = []
for i in range(Params.shape[0]):
    f = Params["fold_num"].values[i]
    e = Params["num_estimators"].values[i]
    d = Params["max_depth"].values[i]
    fn_out = f"random_forest_fold_num_{f}_x_max_depth_{d}_x_num_estimators_{e}.csv"
    fn_out_list.append(fn_out)
Params["fn_out"] = fn_out_list

# Test models
Output = pd.DataFrame(columns=["fold_num", "num_estimators", "max_depth", "rmse"])
for i in range(Params.shape[0]):
    XTrain = np.load(Params["train_x"].values[i])
    y_train = np.load(Params["train_y"].values[i])

    XTest = np.load(Params["test_x"].values[i])
    y_test = np.load(Params["test_y"].values[i])

    f = Params["fold_num"].values[i]
    e = Params["num_estimators"].values[i]
    d = Params["max_depth"].values[i]
    fn_out = Params["fn_out"].values[i]

    print(i, "/", Params.shape[0])

    reg = RandomForestRegressor(n_estimators=e, max_depth=d)
    reg.fit(X=XTrain, y=y_train.ravel())
    y_fit = reg.predict(XTest)

    # RMSE
    errors = y_fit - y_test.transpose()
    se = np.square(errors)
    mse = np.mean(se)
    rmse = np.sqrt(mse)

    # Record RMSE
    new_row = [f, e, d, rmse]
    Output.loc[len(Output)] = new_row
    Output.to_csv("random_forest_search_1.csv")
exit()
