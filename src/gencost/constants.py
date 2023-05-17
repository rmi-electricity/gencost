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
}
FUEL_GROUP_MAP = UDAY_FOSSIL_FUEL_MAP | {
    "ANT": "coal",
    "AB": "biofuel",  # other in fuel_group_emissions_map
    "MSW": "biofuel",  # other in fuel_group_emissions_map
    "OBS": "biofuel",  # other in fuel_group_emissions_map
    "WDS": "biofuel",  # other in fuel_group_emissions_map
    "OBL": "biofuel",  # other in fuel_group_emissions_map
    "SLW": "biofuel",  # other in fuel_group_emissions_map
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
    "TDF": "other",
    "MWH": "other",
    "OTH": "other",
    "MSN": "other",
    "PUR": "other",
    "SC": "coal",
}

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
    "age_from_report_year",
    "avg_age_from_report_year",
    "current_avg_age",
    "age_of_observation",
    "age_relative_to_avg",
    "pollution_control_costs_per_kw",
]
