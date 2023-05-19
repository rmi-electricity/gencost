from functools import lru_cache

import pandas as pd

from gencost.constants import CARB_INTENSITY, COST_FLOOR

TECH_MAP = {
    "Biopower_Dedicated": "Wood/Wood Waste Biomass",
    "Coal_FE_newAvgCF": "Conventional Steam Coal",
    # "Geothermal_HydroFlash": "Geothermal",
    # "Hydropower_NPD1": "Conventional Hydroelectric",
    # "Hydropower_NPD2": "Conventional Hydroelectric",
    # "Hydropower_NPD3": "Conventional Hydroelectric",
    # "Hydropower_NPD4": "Conventional Hydroelectric",
    # "Hydropower_NPD5": "Conventional Hydroelectric",
    # "Hydropower_NPD6": "Conventional Hydroelectric",
    # "Hydropower_NPD7": "Conventional Hydroelectric",
    # "Hydropower_NPD8": "Conventional Hydroelectric",
    # "Hydropower_NSD1": "Conventional Hydroelectric",
    # "Hydropower_NSD2": "Conventional Hydroelectric",
    # "Hydropower_NSD3": "Conventional Hydroelectric",
    # "Hydropower_NSD4": "Conventional Hydroelectric",
    # "LandbasedWind_Class1": "Onshore Wind Turbine",
    # "LandbasedWind_Class10": "Onshore Wind Turbine",
    # "LandbasedWind_Class2": "Onshore Wind Turbine",
    # "LandbasedWind_Class3": "Onshore Wind Turbine",
    # "LandbasedWind_Class4": "Onshore Wind Turbine",
    # "LandbasedWind_Class5": "Onshore Wind Turbine",
    # "LandbasedWind_Class6": "Onshore Wind Turbine",
    # "LandbasedWind_Class7": "Onshore Wind Turbine",
    # "LandbasedWind_Class8": "Onshore Wind Turbine",
    # "LandbasedWind_Class9": "Onshore Wind Turbine",
    "NaturalGas_FE_CCAvgCF": "Natural Gas Fired Combined Cycle",
    "NaturalGas_FE_CTAvgCF": "Natural Gas Fired Combustion Turbine",
    # "Nuclear_Nuclear": "Nuclear",
    # "OffShoreWind_Class1": "Offshore Wind Turbine",
    # "OffShoreWind_Class10": "Offshore Wind Turbine",
    # "OffShoreWind_Class11": "Offshore Wind Turbine",
    # "OffShoreWind_Class12": "Offshore Wind Turbine",
    # "OffShoreWind_Class13": "Offshore Wind Turbine",
    # "OffShoreWind_Class14": "Offshore Wind Turbine",
    # "OffShoreWind_Class2": "Offshore Wind Turbine",
    # "OffShoreWind_Class3": "Offshore Wind Turbine",
    # "OffShoreWind_Class4": "Offshore Wind Turbine",
    # "OffShoreWind_Class5": "Offshore Wind Turbine",
    # "OffShoreWind_Class6": "Offshore Wind Turbine",
    # "OffShoreWind_Class7": "Offshore Wind Turbine",
    # "OffShoreWind_Class8": "Offshore Wind Turbine",
    # "OffShoreWind_Class9": "Offshore Wind Turbine",
    # "Pumped Storage Hydropower_NatlClass1": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass10": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass11": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass12": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass13": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass14": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass15": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass2": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass3": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass4": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass5": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass6": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass7": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass8": "Hydroelectric Pumped Storage",
    # "Pumped Storage Hydropower_NatlClass9": "Hydroelectric Pumped Storage",
    # "Utility-Scale Battery Storage_10Hr Battery Storage": "Batteries",
    # "Utility-Scale Battery Storage_2Hr Battery Storage": "Batteries",
    # "Utility-Scale Battery Storage_4Hr Battery Storage": "Batteries",
    # "Utility-Scale Battery Storage_6Hr Battery Storage": "Batteries",
    # "Utility-Scale Battery Storage_8Hr Battery Storage": "Batteries",
    # "UtilityPV_Class1": "Solar Photovoltaic",
    # "UtilityPV_Class10": "Solar Photovoltaic",
    # "UtilityPV_Class2": "Solar Photovoltaic",
    # "UtilityPV_Class3": "Solar Photovoltaic",
    # "UtilityPV_Class4": "Solar Photovoltaic",
    # "UtilityPV_Class5": "Solar Photovoltaic",
    # "UtilityPV_Class6": "Solar Photovoltaic",
    # "UtilityPV_Class7": "Solar Photovoltaic",
    # "UtilityPV_Class8": "Solar Photovoltaic",
    # "UtilityPV_Class9": "Solar Photovoltaic",
}
VAR_MAP = {
    "Fixed O&M": "fom_per_kw",
    "Fuel": "fuel_per_mwh",
    "Variable O&M": "vom_per_mwh",
    "CAPEX": "capex_per_kw",
}
HR = {
    "Wood/Wood Waste Biomass": 13.5,  # ATB 2022 v2 Biopower Dedicated
    "Conventional Steam Coal": 8.48894,  # ATB 2022 v2 Coal-new
    "Natural Gas Fired Combined Cycle": 6.363,  # ATB 2022 v2 NG F-Frame CC
    "Natural Gas Fired Combustion Turbine": 9.717,  # ATB 2022 v2 NG F-Frame CT
    "Nuclear": 10.461,  # ATB 2022 v2
}


@lru_cache
def dl_atb():
    """Download and format ATBe data."""
    return (
        pd.read_parquet(
            "https://oedi-data-lake.s3.amazonaws.com/ATB/electricity/parquet/2022/ATBe.parquet"
        )
        .query(
            "core_metric_case == 'Market' "
            "& core_metric_parameter in @VAR_MAP "
            "& scenario == 'Moderate' "
            "& crpyears  == '30'"
        )
        .assign(
            technology_description=lambda x: x.technology.str.cat(
                x.techdetail, sep="_"
            ).map(TECH_MAP),
            variable=lambda x: x.core_metric_parameter.map(VAR_MAP),
            year=lambda x: x.core_metric_variable.astype(int),
            start_per_kw=0,
            heat_rate=lambda x: x.technology_description.map(HR),
            co2_factor=lambda x: x.technology_description.map(CARB_INTENSITY),
        )
        .dropna(subset="technology_description")
        .pivot(
            index=[
                "technology_description",
                "techdetail",
                "year",
                "start_per_kw",
                "heat_rate",
                "co2_factor",
            ],
            columns="variable",
            values="value",
        )
        .reset_index()
        .assign(
            fuel_per_mwh=lambda x: x.fuel_per_mwh.fillna(
                x.technology_description.map(
                    COST_FLOOR.set_index("technology_description").fuel_floor.to_dict()
                )
            ),
        )
    )


def get_atb(df: pd.DataFrame, years: tuple = (2008, 2021), how="inner"):
    """Get ATB cost data for multiple years for provided plants.

    Args:
        df: plants to get ATB data for, columns must include:
            - plant_id_eia
            - generator_id
            - operating_date / generator_operating_date
            - technology_description
            - final_ba_code / balancing_authority_code_eia
        years: inputs to range to define years of data to get,
            (the last year is not included)
        how: how to merge on the ATB data (df is left, atb is right).

    Returns:

    """
    _o = ("operating_date", "generator_operating_date")
    _b = ("final_ba_code", "balancing_authority_code_eia")
    op_col = [c for c in _o if c in df]
    ba_col = [c for c in _b if c in df]
    for col, opt in ((op_col, _o), (ba_col, _b)):
        if not col:
            raise ValueError(f"`df` must contain one of these columns: {opt}")
    if missing := {"plant_id_eia", "generator_id", "technology_description"} - set(df):
        raise ValueError(f"`df` is missing required columns: {missing}")

    atb = (
        df.assign(
            year_=lambda x: x[op_col[0]].dt.year,
            year=lambda x: x.year_.mask(x.year_ < 2020, 2020),
        )
        .reset_index()
        .merge(
            dl_atb(),
            on=["technology_description", "year"],
            how=how,
            validate="1:m",
        )
    )
    dt_range = pd.to_datetime(range(*years), format="%Y")
    return (
        pd.concat(atb.assign(datetime=dt) for dt in dt_range)
        .set_index(["plant_id_eia", "generator_id", "datetime"])
        .sort_index()[
            [
                ba_col[0],
                "vom_per_mwh",
                "fuel_per_mwh",
                "fom_per_kw",
                "start_per_kw",
                "heat_rate",
                "co2_factor",
            ]
        ]
    )
