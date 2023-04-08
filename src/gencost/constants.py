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
    "AB": "biofuel",
    "MSW": "biofuel",
    "OBS": "biofuel",
    "WDS": "biofuel",
    "OBL": "biofuel",
    "SLW": "biofuel",
    "BLQ": "biofuel",
    "WDL": "biofuel",
    "LFG": "biofuel",
    "OBG": "biofuel",
    "MSB": "biofuel",
    "SUN": "renew",
    "WND": "renew",
    "GEO": "renew",
    "WAT": "renew",
    "NUC": "nuclear",
    "WH": "waste_heat",
    "TDF": "other",
    "MWH": "charge",
    "OTH": "other",
    "MSN": "other",
    "PUR": "steam",
    "SC": "coal",
}
