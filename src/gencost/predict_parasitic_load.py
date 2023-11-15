"""
Using DataBySubplant as ground truth, fit a random forest regressor, and predict a new data set's
parasitic load.
"""

import numpy as np

# import pandas as pd
import pandera as pa
from sklearn.ensemble import RandomForestRegressor
from sklearn.preprocessing import OneHotEncoder, StandardScaler


def check_data_by_subplant(input_data, is_data_by_subplant=True):
    """
    Ensure DataBySubplant has all of the columns and rows we need.
    Arguments:
        input_data=DataBySubplant (or the new data to be inputted into the model). The only difference is that DataBySubplant needs gross_generation_mwh in order to calculate the dependent variable.
        is_data_by_subplant=Boolean; if FALSE, don't look for gross_generation_mwh
    Returns:
        Nothing, just performs checks, and returns a pandera error if any check fails.
    """

    reference = "DataBySubplant" if is_data_by_subplant else "New data"
    print(f"{reference} QC")

    schema = pa.DataFrameSchema(
        {
            "prime_mover": pa.Column(str, nullable=True),
            "state": pa.Column(str, nullable=True),
            "capacity_mw": pa.Column(float, nullable=True),
            "net_generation_mwh": pa.Column(float, nullable=True),
            "associated_combined_heat_power": pa.Column(float, nullable=True),
            "duct_burners": pa.Column(float, nullable=True),
            "bypass_heat_recovery": pa.Column(float, nullable=True),
            "solid_fuel_gasification": pa.Column(float, nullable=True),
            "carbon_capture": pa.Column(float, nullable=True),
            "fluidized_bed_tech": pa.Column(float, nullable=True),
            "pulverized_coal_tech": pa.Column(float, nullable=True),
            "stoker_tech": pa.Column(float, nullable=True),
            "other_combustion_tech": pa.Column(float, nullable=True),
            "subcritical_tech": pa.Column(float, nullable=True),
            "supercritical_tech": pa.Column(float, nullable=True),
            "ultrasupercritical_tech": pa.Column(float, nullable=True),
            "age_in_report_year": pa.Column(float, nullable=True),
            "age_in_current_year": pa.Column(float, nullable=True),
            "age_of_observation": pa.Column(float, nullable=True),
            "age_relative_to_prime_avg": pa.Column(float, nullable=True),
            "pollution_control_costs_per_kw": pa.Column(float, nullable=True),
            "biofuel_net_mwh": pa.Column(float, nullable=True),
            "coal_net_mwh": pa.Column(float, nullable=True),
            "natural_gas_net_mwh": pa.Column(float, nullable=True),
            "other_net_mwh": pa.Column(float, nullable=True),
            "other_gas_net_mwh": pa.Column(float, nullable=True),
            "petroleum_net_mwh": pa.Column(float, nullable=True),
            "petroleum_coke_net_mwh": pa.Column(float, nullable=True),
        },
        checks=pa.Check(
            lambda df: df.shape[0] > 0, name="Table must contain at least 1 row"
        ),
    )

    schema_gross_gen = pa.DataFrameSchema(
        {"gross_generation_mwh": pa.Column(float, nullable=True)}
    )

    schema.validate(input_data)
    if is_data_by_subplant:
        schema_gross_gen.validate(input_data)

    print(f"{reference} QC results: pass")


def feature_engineering(databysubplant, newdata):
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
    num = databysubplant["gross_generation_mwh"] - databysubplant["net_generation_mwh"]
    denom = databysubplant["capacity_mw"] * 8760.0
    databysubplant["parasitic_load"] = num / denom

    # Filter unusable values
    #   Base version always excludes negative parasitic load
    #   Future versions will exclude parasitic loads > 1
    mask_prime_mover = databysubplant["prime_mover"].isin(["CC", "GT", "ST"])
    mask_parasitic_load = databysubplant["parasitic_load"] >= 0.0
    databysubplant = databysubplant.loc[mask_prime_mover & mask_parasitic_load]

    # Distinguish between string and number inputs; and parasitic_load
    # barring possible reshape(-1, 1), this is ready
    trainstr = databysubplant[predictors_str]
    trainnum = databysubplant[predictors_num]
    newdatastr = newdata[predictors_str]
    newdatanum = newdata[predictors_num]

    # make IVs numerical with one-hot encoding; rejoin all data
    enc.fit(trainstr)
    trainstrenc = enc.transform(trainstr).toarray()
    newdatastrenc = enc.transform(newdatastr).toarray()

    trainstep1 = np.concatenate((trainstrenc, trainnum.to_numpy()), axis=1)
    newdatastep1 = np.concatenate((newdatastrenc, newdatanum.to_numpy()), axis=1)

    # scale data
    scaler.fit(trainstep1)
    trainstep2 = scaler.transform(trainstep1)
    newdatastep2 = scaler.transform(newdatastep1)

    # Replace missing values with zero
    # https://stackoverflow.com/questions/60443779/how-to-replacing-all-missing-values-in-numpy-array-with-0-and-displaying-the-las
    mask_train = np.isnan(trainstep2)
    trainstep2[np.where(mask_train)] = 0.0

    mask_new_data = np.isnan(newdatastep2)
    newdatastep2[np.where(mask_new_data)] = 0.0

    # Return data
    x = trainstep2
    y = databysubplant["parasitic_load"].to_numpy()
    xnew = newdatastep2

    return x, y, xnew


def get_y_fit(x, y, xnew):
    """
    Fit a random forest regressor, output new values for NewData; this is the parasitic_load
    """
    reg = RandomForestRegressor(n_estimators=1, max_depth=250)
    reg.fit(X=x, y=y)
    y_fit = reg.predict(xnew)
    return y_fit


def predict_parasitic_load(databysubplant, newdata):
    """
    Pull all previous functions together:
        data QC
        data cleaning/feature engineering
        and predict parasitic_load
    """
    check_data_by_subplant(databysubplant, is_data_by_subplant=True)
    check_data_by_subplant(newdata, is_data_by_subplant=False)
    x, y, xnew = feature_engineering(databysubplant, newdata)
    y_fit = get_y_fit(x, y, xnew)
    newdata["parasitic_load"] = y_fit
    return newdata
