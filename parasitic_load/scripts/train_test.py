import os

import pandas as pd
from numpy.random import choice, seed

seed(1)

os.chdir("/Users/andrewbartnof/Documents/rmi/gencost/parasitic_load")
DataBySubplant = pd.read_csv("clean_data_py/data_by_subplant.csv")

# split into five cross-validation parts
# save to disk

num_rows = DataBySubplant.shape[0]
fold_range = range(1, 6)
splitting_vector = choice(a=fold_range, size=num_rows, replace=True)

for fold_num in fold_range:
    test_mask = splitting_vector == fold_num
    train_mask = ~test_mask

    Train = DataBySubplant.loc[train_mask]
    Test = DataBySubplant.loc[test_mask]

    train_fn = "clean_data_py/train/train_" + str(fold_num) + ".csv"
    test_fn = "clean_data_py/test/test_" + str(fold_num) + ".csv"

    Train.to_csv(train_fn, index=False)
    Test.to_csv(test_fn, index=False)
