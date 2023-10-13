"""
Run qc,
"""

import os

import numpy as np
import pandas as pd
import predict_parasitic_load

os.chdir("/Users/andrewbartnof/Documents/rmi/gencost/parasitic_load")
DataBySubplant = pd.read_parquet("input_data/subplant_w_tech_by_capacity.parquet")

# y_fit
Output = predict_parasitic_load.predict_parasitic_load(
    DataBySubplant=DataBySubplant, NewData=DataBySubplant
)
y_fit = Output["parasitic_load"].to_numpy()

# y_true
num = DataBySubplant["gross_generation_mwh"] - DataBySubplant["net_generation_mwh"]
denom = DataBySubplant["capacity_mw"] * 8760.0
y_true = num / denom
y_true = y_true.to_numpy()

e = y_fit - y_true
se = np.square(e)
mse = np.mean(se)
rmse = np.sqrt(mse)

Residuals = pd.DataFrame({"residual": e, "y_true": y_true, "y_fit": y_fit})

# The rows with bad residuals are the ones where y_true are negative, which should be impossible
print(Residuals.sort_values(by=["residual"], ascending=False).head())
