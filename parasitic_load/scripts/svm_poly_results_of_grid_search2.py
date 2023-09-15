# best model: cost = 767   rmse = 0.111069

import os

import numpy as np
import pandas as pd

os.chdir(
    "/Users/andrewbartnof/Documents/rmi/gencost/parasitic_load/clean_data/svm/svm_poly_2/search2"
)
fn_list = os.listdir()
# fn_list = fn_list[0:5]  # TODO remove this

# Load data
data_list = [pd.read_csv(fn) for fn in fn_list]
Data = pd.concat(data_list)

# RMSE
Data["residual"] = Data["y_fit"] - Data["y_true"]
Data["residual2"] = Data["residual"].apply(np.square)

Agg = (
    Data[["fold_num", "cost", "residual2"]]
    .groupby(["fold_num", "cost"])
    .agg(mean_residual2=pd.NamedAgg(column="residual2", aggfunc="mean"))
    .reset_index()
)
Agg["rmse"] = Agg["mean_residual2"].apply(np.sqrt)
Agg = Agg[["fold_num", "cost", "rmse"]]

MeanRmse = (
    Agg.groupby(["cost"])
    .agg(mean_rmse=pd.NamedAgg(column="rmse", aggfunc="mean"))
    .reset_index()
)
print(MeanRmse.sort_values(by=["mean_rmse"], ascending=True))


# Plot 5-fold RMSE:
# Agg.plot.scatter(x='cost', y='rmse', title='5-fold')
# plt.xlabel("Cost")
# plt.ylabel("RMSE")
# plt.show(block=True)
