#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Apr  4 09:58:35 2023

@author: andrewbartnof
"""

import pandas as pd
import numpy as np
import os
from sklearn.model_selection import (
    train_test_split,  # noqa: F401
    ShuffleSplit,
    cross_val_score,
)
from sklearn.impute import SimpleImputer
from sklearn.metrics import mean_squared_error


os.chdir("Documents/rmi/power_plant_characteristics/")
RawData = pd.read_parquet("input_data/data_for_pf_subplants.parquet")

RawData.columns  # noqa: B018

# Excluding the following columns:
# 'plant_id_eia', 'pf_subplant_id', 'report_date', 'utility_id_eia',
# 'plant_name_eia', 'latitude', 'longitude', 'geoid', 'state_id', 'county_id',
# 'census_tract_id', 'block_group_id', 'respondent_id'
good_columns = [
    "capacity_mw",
    "net_generation_mwh",
    "fuel_consumed_for_electricity_mmbtu",
    "generator_starts",
    "fuel_starts",
    "gross_generation_mwh",
    "heat_in_mmbtu",
    "co2_tons",
    "camd_capacity_mw",
    "state",
    "balancing_authority_code_eia",
    "operational_capacity_in_report_year",
    "technology_1",
    "energy_source_code_860m",
    "fuel_group_energy_source_code_860m",
    "multiple_fuels",
    "cofire_fuels",
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
    "sector",
    "final_gen_type",
    "rmi_energy_source_code_1",
    "rmi_energy_source_code_2",
    "rmi_energy_source_code_3",
    "rmi_energy_source_code_4",
    "rmi_energy_source_code_5",
    "rmi_energy_source_code_6",
    "retirement_month",
    "retirement_year",
    "planned_retirement_month",
    "planned_retirement_year",
    "fuel_group_rmi_energy_source_code_2",
    "fuel_group_rmi_energy_source_code_3",
    "fuel_group_rmi_energy_source_code_4",
    "fuel_group_rmi_energy_source_code_5",
    "fuel_group_rmi_energy_source_code_6",
    "rmi_fuel_group_1",
    "rmi_fuel_group_2",
    "rmi_fuel_group_3",
    "rmi_fuel_group_4",
    "prime_mover",
    "fuel_group_rmi_energy_source_code_1",
    "fuel_code_coal",
    "fuel_code_natural_gas",
    "fuel_code_other_gas",
    "fuel_code_petroleum",
    "fuel_code_petroleum_coke",
    "age",
    "age_as_of_2021",
    "avg_plant_prime_fuel_age",
    "diff_age_and_avg_plant_prime_fuel",
    "pollution_control_costs_per_kw",
    "utility_name",
    "patio_ba_code",
    "operating_date",
    "net_cf",
    "net_hr",
    "gross_cf",
    "gross_hr",
    "parasitic_load_pct",
]

Data = RawData[good_columns]
# Use generator starts as a DV- this is a complete variable
Data["generator_starts"].isna().mean()


Data.describe()
imp = SimpleImputer(missing_values=np.nan, strategy="mean")

yy = Data["generator_starts"].values.reshape(-1, 1)
cv = ShuffleSplit(n_splits=5, test_size=0.3, random_state=0)
cv()

cv  # noqa: B018

cross_val_score(clf, X, y, cv=cv)  # noqa: F821

mean_squared_error(y_true, y_pred)  # noqa: F821

print(cross_val_score(estimator=imp, y=yy, cv=cv, scoring="mean_squared_error"))


cross_val_score  # noqa: B018
