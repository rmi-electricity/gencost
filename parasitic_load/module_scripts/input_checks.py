#!/usr/bin/env python
""" Workflow:
- Check input files to make sure they pass all checks:
    - Contain necessary columns
    - Columns are the right type
    - Have some rows
- This script can accept either DataBySubplant (training data) or a new data set.
    - If the data being tested is DataBySubplant, then we need 'gross_generation_mwh' in order to create the dependent variable, 'parasitic_load'.
    - If it is not DataBySubplant (ie if it is new data whose parasitic_load will be predicted), then we don't need to look for 'gross_generation_mwh'.

Andrew Bartnof, for RMI
2023
"""

import os

import pandas as pd
import pandera as pa

os.chdir("/Users/andrewbartnof/Documents/rmi/gencost/parasitic_load")
DataBySubplant = pd.read_parquet("input_data/subplant_w_tech_by_capacity.parquet")


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


check_data_by_subplant(DataBySubplant)
