#!/usr/bin/env python3
# ruff: noqa: N803, N806, F401
"""
Fit random forest models
- load X_train, y_train, X_test
- establish parameters to be tested: 1 estimator, depth = 250
- fit model
- predict X_test
Andrew Bartnof, for RMI
2023
"""

import os

import numpy as np

# import pandas as pd
from sklearn.ensemble import RandomForestRegressor

os.chdir("/Users/andrewbartnof/Documents/rmi/gencost/parasitic_load/")
X = np.load("X.npy")
XNew = np.load("XNew.npy")
y = np.load("y.npy")

# START FUNCTION HERE


def predict_parasitic_load(X, y, XNew):
    reg = RandomForestRegressor(n_estimators=1, max_depth=250)
    reg.fit(X=X, y=y)
    y_fit = reg.predict(XNew)
    return y_fit
