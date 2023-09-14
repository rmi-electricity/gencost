import os

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

os.chdir(
    "/Users/andrewbartnof/Documents/rmi/gencost/parasitic_load/clean_data/svm/svm_poly_1/search1"
)
fn_list = os.listdir()
# fn_list = fn_list[0:5]  # TODO remove this

data_list = [pd.read_csv(fn) for fn in fn_list]
Data = pd.concat(data_list)
Data["residual"] = Data["y_fit"] - Data["y_true"]
Data["residual2"] = Data["residual"].apply(np.square)
Agg = (
    Data[["power", "cost", "residual2"]]
    .groupby(["power", "cost"])
    .agg(mean_residual2=pd.NamedAgg(column="residual2", aggfunc="mean"))
    .reset_index()
)
Agg["rmse"] = Agg["mean_residual2"].apply(np.sqrt)
Agg = Agg[["power", "cost", "rmse"]]

print(Agg.nsmallest(10, "rmse"))

Wide = Agg.pivot(index="cost", columns="power", values="rmse")
Wide.plot.line()
plt.xlabel("Cost")
plt.ylabel("RMSE")
plt.show(block=True)
# Agg.to_csv('~/Downloads/rmse.csv', index=False)
