#!/usr/bin/env python
"""
Perform feature engineering on cleaned data, so that it's ready for modeling:
    - encode categorical data as numeric
    - scale all data
    - impute missing rows
Andrew Bartnof, for RMI
2023
"""

import os

import numpy as np
import pandas as pd
from sklearn.preprocessing import OneHotEncoder, StandardScaler

os.chdir("/Users/andrewbartnof/Documents/rmi/gencost/parasitic_load")
enc = OneHotEncoder(handle_unknown="ignore")
scaler = StandardScaler(copy=True, with_mean=True, with_std=True)

fold_range = range(1, 6)
for fold_num in fold_range:
    # Define filenames, read csv dataset
    fn_train_in = "clean_data_py/train/train_" + str(fold_num) + ".csv"
    fn_test_in = "clean_data_py/test/test_" + str(fold_num) + ".csv"

    fn_train_x_out = "clean_data_py/train/train_x_" + str(fold_num) + ".npy"
    fn_train_y_out = "clean_data_py/train/train_y_" + str(fold_num) + ".npy"

    fn_test_x_out = "clean_data_py/test/test_x_" + str(fold_num) + ".npy"
    fn_test_y_out = "clean_data_py/test/test_y_" + str(fold_num) + ".npy"

    Train = pd.read_csv(fn_train_in)
    Test = pd.read_csv(fn_test_in)

    # Remove gross_generation_mwh
    Train = Train.drop(["gross_generation_mwh"], axis=1)
    Test = Test.drop(["gross_generation_mwh"], axis=1)

    # distinguish between IVs and DV
    y_train = Train["parasitic_load"].to_numpy().reshape(-1, 1)
    y_test = Test["parasitic_load"].to_numpy().reshape(-1, 1)

    Train = Train.drop("parasitic_load", axis="columns")
    Test = Test.drop("parasitic_load", axis="columns")

    # make IVs numerical with one-hot encoding
    TrainCategorical = Train.select_dtypes(exclude=["number"])
    TrainNumeric = Train.select_dtypes(include=["number"])

    TestCategorical = Test.select_dtypes(exclude=["number"])
    TestNumeric = Test.select_dtypes(include=["number"])

    enc.fit(TrainCategorical)
    TrainEnc = enc.transform(TrainCategorical).toarray()
    TestEnc = enc.transform(TestCategorical).toarray()

    TrainStep1 = np.concatenate((TrainEnc, TrainNumeric), axis=1)
    TestStep1 = np.concatenate((TestEnc, TestNumeric), axis=1)

    # Scale data
    scaler.fit(TrainStep1)
    TrainStep2 = scaler.transform(TrainStep1)
    TestStep2 = scaler.transform(TestStep1)

    # Replace missing values with zero
    # https://stackoverflow.com/questions/60443779/how-to-replacing-all-missing-values-in-numpy-array-with-0-and-displaying-the-las
    # a[np.where(np.isnan(a))] = 0
    mask_train = np.isnan(TrainStep2)
    TrainStep2[np.where(mask_train)] = 0.0

    mask_test = np.isnan(TestStep2)
    TestStep2[np.where(mask_test)] = 0.0

    # write cleaned training/testing datasets to disk
    np.save(file=fn_train_x_out, arr=TrainStep2)
    np.save(file=fn_test_x_out, arr=TestStep2)

    np.save(file=fn_train_y_out, arr=y_train)
    np.save(file=fn_test_y_out, arr=y_test)
