#!/usr/bin/env python
# ruff: noqa: N803, N806
"""
Perform feature engineering on cleaned data, so that it's ready for modeling
Andrew Bartnof, for RMI
2023
"""

import os

import numpy as np
import pandas as pd
from sklearn.preprocessing import OneHotEncoder, StandardScaler

os.chdir("/Users/andrewbartnof/Documents/rmi/gencost/parasitic_load")

DataBySubplant = pd.read_csv("clean_data_py/data_by_subplant.csv")
NewData = pd.read_csv("clean_data_py/data_by_subplant.csv")


# start function here
def feature_engineering(DataBySubplant, NewData):
    """
    Perform feature engineering on cleaned data, so that it's ready for modeling:
        - add parasitic load to DataBySubplant
            - remove gross_generation_mwh
        - select only predictors (and for DataBySubplant, parasitic_load as output value)
        - encode categorical data as numeric
        - scale all data
        - impute missing rows
    Arguments:
        DataBySubplant: Pandas table, use this as the 'training' set for the model
        NewData: Pandas table with the same columns as DataBySubplant (excluding gross_generation_mwh, which is used to calculate parasitic_load); this will be scaled, encoded, etc just like DataBySubplant. The model will predict new values for NewData in a subsequent step.
    Returns:
        X: Numpy array used as predictors for the model
        y: Ground truth values for training the model (corresponds with TrainStep2)
        XNew: Numpy array, fed into model, and we'll get fitted values for this
    """

    # Initialize variables
    enc = OneHotEncoder(handle_unknown="ignore")
    scaler = StandardScaler(copy=True, with_mean=True, with_std=True)

    predictors_str = ["prime_mover", "state"]

    predictors_num = [
        "capacity_mw",
        "net_generation_mwh",
        "associated_combined_heat_power",
        "duct_burners",
        "bypass_heat_recovery",
        "solid_fuel_gasification",
        "carbon_capture",
        "fluidized_bed_tech",
        "pulverized_coal_tech",
        "stoker_tech",
        "other_combustion_tech",
        "subcritical_tech",
        "supercritical_tech",
        "ultrasupercritical_tech",
        "age_in_report_year",
        "age_in_current_year",
        "age_of_observation",
        "age_relative_to_prime_avg",
        "pollution_control_costs_per_kw",
        "biofuel_net_mwh",
        "coal_net_mwh",
        "natural_gas_net_mwh",
        "other_net_mwh",
        "other_gas_net_mwh",
        "petroleum_net_mwh",
        "petroleum_coke_net_mwh",
    ]

    # Add parasitic load to DataBySubplant
    num = DataBySubplant["gross_generation_mwh"] - DataBySubplant["net_generation_mwh"]
    denom = DataBySubplant["capacity_mw"] * 8760.0
    DataBySubplant["parasitic_load"] = num / denom

    # Filter unusable values
    #   Base version always excludes negative parasitic load
    #   Future versions will exclude parasitic loads > 1
    mask_prime_mover = DataBySubplant["prime_mover"].isin(["CC", "GT" "ST"])
    mask_parasitic_load = DataBySubplant["parasitic_load"] >= 0.0
    DataBySubplant = DataBySubplant.loc[mask_prime_mover & mask_parasitic_load]

    # Distinguish between string and number inputs; and parasitic_load
    y_train = DataBySubplant[
        "parasitic_load"
    ].to_numpy()  # barring possible reshape(-1, 1), this is ready

    TrainStr = DataBySubplant[predictors_str]
    TrainNum = DataBySubplant[predictors_num]
    NewDataStr = NewData[predictors_str]
    NewDataNum = NewData[predictors_num]

    # make IVs numerical with one-hot encoding; rejoin all data
    enc.fit(TrainStr)
    TrainStrEnc = enc.transform(TrainStr).toarray()
    NewDataStrEnc = enc.transform(NewDataStr).toarray()

    TrainStep1 = np.concatenate((TrainStrEnc, TrainNum.to_numpy()), axis=1)
    NewDataStep1 = np.concatenate((NewDataStrEnc, NewDataNum.to_numpy()), axis=1)

    # scale data
    scaler.fit(TrainStep1)
    TrainStep2 = scaler.transform(TrainStep1)
    NewDataStep2 = scaler.transform(NewDataStep1)

    # Replace missing values with zero
    # https://stackoverflow.com/questions/60443779/how-to-replacing-all-missing-values-in-numpy-array-with-0-and-displaying-the-las
    mask_train = np.isnan(TrainStep2)
    TrainStep2[np.where(mask_train)] = 0.0

    mask_new_data = np.isnan(NewDataStep2)
    NewDataStep2[np.where(mask_new_data)] = 0.0

    # Return data
    X = TrainStep2
    y = y_train
    XNew = NewDataStep2
    return X, y, XNew


# use np.save to put these on disk for now
# X, XNew, y = feature_engineering(DataBySubplant, NewData)
