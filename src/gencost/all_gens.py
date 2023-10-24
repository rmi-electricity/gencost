import warnings
import pandas as pd
import numpy as np
from gencost.crosswalk import Crosswalk
from gencost.waterfall import DataBySubplant
from gencost.entity_ids import add_ba_code

FOSSIL_PRIME_MOVER_MAP = {
    "ST": "ST",  # steam turbine
    "GT": "GT",  # gas turbine xCC
    "IC": "IC",  # internal combustion
    "CA": "CC",  # steam part of CC
    "CT": "CC",  # gas turbine part of CC
    "CS": "CC",  # single shaft CC
    "CC": "CC",  # CC in planning
}

UDAY_FOSSIL_FUEL_MAP = {  # the better map from Uday
    "ANT": "coal",
    "BIT": "coal",
    "LIG": "coal",
    "SGC": "coal",
    "SUB": "coal",
    "WC": "coal",
    "RC": "coal",
    "DFO": "petroleum",
    "JF": "petroleum",
    "KER": "petroleum",
    "PC": "petroleum_coke",
    "PG": "petroleum",
    "RFO": "petroleum",
    "SGP": "other_gas",
    "WO": "petroleum",
    "BFG": "other_gas",
    "NG": "natural_gas",
    "OG": "other_gas",
    "SC": "coal",
    "TDF": "petroleum",
}

# base
xwalk = Crosswalk()
# self to be able to copy / paste from waterfall.py for dev ease
self = DataBySubplant(xwalk)


def get_all_gens(latest_month_year_860m):
    """
    latest_month_year_860m (str):
    latest month/year reported in 860m in YYYY-MM-DD format

    """
    return (
        self.pudl_tabl.gens_eia860m()
        .pipe(add_ba_code)
        .query("report_date == @latest_month_year_860m")
        .assign(
            prime_mover=lambda x: x["prime_mover_code"].map(FOSSIL_PRIME_MOVER_MAP),
            fuel_group_code=lambda x: x["energy_source_code_1"].map(
                UDAY_FOSSIL_FUEL_MAP
            ),
            operating_date=lambda x: x["generator_operating_date"],
            retirement_date=lambda x: x["generator_retirement_date"],
        )
    ).to_parquet(
        "/Users/mcastillo/GitHub/patio-model/notebooks/baseline_outputs/all_gens.parquet"
    )
