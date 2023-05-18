import pandas as pd

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
FUEL_GROUP_MAP = UDAY_FOSSIL_FUEL_MAP | {
    "AB": "biofuel",  # other in fuel_group_emissions_map
    "MSW": "other",  # other in fuel_group_emissions_map
    "OBS": "biofuel",  # other in fuel_group_emissions_map
    "WDS": "biofuel",  # other in fuel_group_emissions_map
    "OBL": "biofuel",  # other in fuel_group_emissions_map
    "SLW": "other",  # other in fuel_group_emissions_map
    "BLQ": "biofuel",  # other in fuel_group_emissions_map
    "WDL": "biofuel",  # other in fuel_group_emissions_map
    "LFG": "biofuel",  # other in fuel_group_emissions_map
    "OBG": "biofuel",  # other in fuel_group_emissions_map
    "MSB": "biofuel",  # other in fuel_group_emissions_map
    "SUN": "renew",  # other in fuel_group_emissions_map
    "WND": "renew",  # other in fuel_group_emissions_map
    "GEO": "renew",  # other in fuel_group_emissions_map
    "WAT": "renew",  # other in fuel_group_emissions_map
    "NUC": "nuclear",  # other in fuel_group_emissions_map
    "WH": "other",
    "MWH": "other",
    "OTH": "other",
    "MSN": "other",
    "PUR": "other",
}
CARB_INTENSITY = {
    "Petroleum Liquids": 0.07509,
    "Natural Gas Steam Turbine": 0.05291,
    "Conventional Steam Coal": 0.09610,
    "Natural Gas Fired Combined Cycle": 0.05291,
    "Natural Gas Fired Combustion Turbine": 0.05291,
    "Natural Gas Internal Combustion Engine": 0.05291,
    "Coal Integrated Gasification Combined Cycle": 0.09610,
    "Other Natural Gas": 0.05291,
    "Petroleum Coke": 0.10212,
    "Natural Gas with Compressed Air Storage": 0.05291,
    "Other Gases": 0.06288,
    "Solar Photovoltaic": 0.0,
    "Onshore Wind Turbine": 0.0,
    "Offshore Wind Turbine": 0.0,
    "Solar": 0.0,
    "Wind": 0.0,
    "Offshore_Wind": 0.0,
    "Wood/Wood Waste Biomass": 0.04989,  # same as MSW
    "Municipal Solid Waste": 0.04989,  # same as MSW
    "Landfill Gas": 0.04989,  # same as MSW
    "All Other": 0.06288,  # same as propane / other gases
    "Other Waste Biomass": 0.04989,  # same as MSW
}
"""
https://www.eia.gov/environment/emissions/co2_vol_mass.php

in tonnes/mmbtu
"""
COST_FLOOR = pd.DataFrame(
    [
        ("Coal Integrated Gasification Combined Cycle", 5.0, 35.0, 0.1, 10.0),
        ("Conventional Steam Coal", 4.0, 25.0, 0.1, 10.0),
        ("Landfill Gas", 4.0, 15.0, 0.1, 10.0),
        ("Municipal Solid Waste", 4.0, 15.0, 0.1, 10.0),
        ("Natural Gas Fired Combined Cycle", 2.0, 20.0, 0.1, 15.0),
        ("Natural Gas Fired Combustion Turbine", 5.0, 15.0, 0.1, 20.0),
        ("Natural Gas Internal Combustion Engine", 4.0, 15.0, 0.1, 15.0),
        ("Natural Gas Steam Turbine", 4.0, 20.0, 0.1, 20.0),
        ("Other Gases", 5.0, 15.0, 0.1, 10.0),
        ("Other Waste Biomass", 4.0, 15.0, 0.1, 10.0),
        ("Petroleum Coke", 5.0, 15.0, 0.1, 30.0),
        ("Petroleum Liquids", 5.0, 15.0, 0.1, 40.0),
        ("Wood/Wood Waste Biomass", 4.0, 15.0, 0.1, 10.0),
    ],
    columns=[
        "technology_description",
        "vom_floor",
        "fom_floor",
        "som_floor",
        "fuel_floor",
    ],
)

GET_860_GEN_COLS = [
    "utility_id_eia",
    "balancing_authority_code_eia",
    "state",
    "plant_id_eia",
    "generator_id",
    "report_date",
    "capacity_mw",
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
]
