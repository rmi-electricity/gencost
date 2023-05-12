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
