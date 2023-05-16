import pandas as pd

from gencost.package_data import PACKAGE_PATH


def add_ba_code(
    input_df: pd.DataFrame, new_ba_col: str = "final_ba_code", drop_interim=False
):
    """Add respondent and final ba_codes.

    Args:
        input_df: frame to add BA / respondent columns to
        new_ba_col: name of ultimate BA code column
        drop_interim: if True, drop all the intermediate respondent / BA code columns

    Returns:

    """
    if missing := {"plant_id_eia", "balancing_authority_code_eia"} - set(input_df):
        raise ValueError(f"`input_df` is missing {missing}")
    ferc_match = pd.read_parquet(
        PACKAGE_PATH / "utility_information.parquet.gzip"
    ).astype({"respondent_id": "Int64"})
    purchased = (
        pd.read_parquet(PACKAGE_PATH / "f1_purchased_power_tagged.parquet.gzip")
        .astype({"respondent_id": "Int64"})
        .query("report_year == 2020 & plant_id_eia.notna()")
        .assign(
            proportion_purchased=lambda x: x.mwh_purchased
            / x.groupby(["plant_id_eia"]).mwh_purchased.transform("sum"),
        )
        .query("proportion_purchased >= 0.9")
        .rename(columns={"respondent_id": "respondent_id_purchaser"})
    )
    out = (
        input_df.merge(
            ferc_match[["respondent_id", "utility_id_eia"]].dropna().drop_duplicates(),
            on="utility_id_eia",
            how="left",
            validate="m:1",
        )
        .merge(
            purchased[["respondent_id_purchaser", "plant_id_eia"]],
            on="plant_id_eia",
            how="left",
            validate="m:1",
        )
        .assign(
            final_respondent_id=lambda x: x.respondent_id.fillna(
                x.respondent_id_purchaser
            )  # .astype("Int64")
        )
        .pipe(adjust_ba_codes, new_ba_col=new_ba_col)
    )
    if drop_interim:
        return out.drop(columns=["respondent_id_purchaser", "final_respondent_id"])
    return out


def adjust_ba_codes(df: pd.DataFrame, new_ba_col="final_ba_code") -> pd.DataFrame:
    """Process for assigning plants to EIA BA codes and FERC 1 Respondent IDs."""
    # Source for PJM FRR data
    # https://www.pjm.com/-/media/markets-ops/rpm/rpm-auction-info/2024-2025/2024-2025-planning-period-parameters-for-base-residual-auction.ashx
    # map https://www.pjm.com/-/media/about-pjm/pjm-zones.ashx
    resps_to_keep = (
        # 12,  # Black hills  (small)
        # 100,  # Entergy Mississippi, LLC (varies over time) -> merged into ENTERGY
        120,  # Northern States Power Co. (MISO)
        130,  # Oklahoma Gas & Electric Co. (SWPP)
        # 144,  # Duke Indiana (PJM) unclear FRR
        166,  # Southwestern Public Service Co. (SWPP)
        177,  # Ameren Missouri (MISO)
        186,  # Dominion Energy Virginia (PJM) DOM is mostly FRR
        # 191,  # Evergy Kansas Central, Inc. (SWPP) -> merged into EVERGY
        193,  # Wisconsin Electric Power Co. (MISO)
        # 194,  # Wisconsin Power & Light Co. (MISO) -> merged into LNT
        195,  # Wisconsin Public Service Corp. (MISO)
        210,  # MidAmerican Energy Co. (MISO)
        22,  # Cleco Power LLC (MISO)
        41,  # Consumers Energy Co. (MISO)
        44,  # DTE Electric Co. (MISO)
        529,  # Tri-State G & T Association (PNM, PSCO, WACM)
        531,  # Basin (OK)
        552,  # Cooperative Energy (MISO, TVA)
        554,  # Dairyland Power Coop (MISO)
        556,  # East Kentucky Power Coop, Inc (LGEE, PJM)
        560,  # Great River Energy (MISO)
        562,  # Hoosier Energy R E C, Inc (MISO)
        # 567,  # North Carolina El Member Corp (too limited)
        58,  # Golden Spread Electric Coop., Inc. (SWPP)
        656,  # Nebraska Public Power District (SWPP)
        658,  # Omaha Public Power District (SWPP)
        # 79,  # Evergy Metro, Inc. (SWPP) -> merged into EVERGY
    )
    ba_replace = {
        "GLHB": "MISO",
        "HGMA": "SRP",
        "HST": "FMPP",
        "SPA": "SWPP",
        "TAL": "FPC",  # TAL is very small, EIA 930 shows it connected to FPC
        "GVL": "FPC",  # GVL is very small, EIA 930 shows it connected to FPC
        "DUK": "DUKE",  # combine Duke Carolinas and Duke Progress
        "CPLE": "DUKE",  # combine Duke Carolinas and Duke Progress
        "BPAT": "PNW",
        "AVA": "PNW",
        "SCL": "PNW",
        "TPWR": "PNW",
        "GRID": "PNW",
        "AVRN": "PNW",
        "IPCO": "PNW",
        "NWMT": "PNW",
        "PGE": "PNW",
        "PSEI": "PNW",
        "CISO": "CAISO",
        "BANC": "CAISO",
        "IID": "CAISO",
        "TIDC": "CAISO",
        "SEPA": "SOCO",  # EIA 930 shows most outgoing transfers to SOCO
    }
    df[new_ba_col] = (
        pd.Series("PAC", index=df.index)
        # Aggregate Pacificorp
        .where(
            df.balancing_authority_code_eia.isin(["PACE", "PACW"])
            | df.final_respondent_id.isin([134]),
            pd.NA,
        )
        .fillna(
            # Aggregate Arizona PS
            pd.Series("APS", index=df.index).where(
                df.balancing_authority_code_eia.isin(["AZPS", "DEAA", "GRIF"])
                | df.final_respondent_id.isin([7]),
                pd.NA,
            ),
        )
        .fillna(
            # breakup SOCO
            df.final_respondent_id.astype(str).where(
                df.balancing_authority_code_eia.isin(["SOCO"])
                # 569 is Oglethorpe
                & df.final_respondent_id.isin([2, 57, 99, 569]),
                pd.NA,
            ),
        )
        .fillna(
            # combine Gulf Power and FPL
            pd.Series("FPL", index=df.index).where(
                df.balancing_authority_code_eia.isin(["FPL"])
                | (
                    df.balancing_authority_code_eia.isin(["SOCO"])
                    & df.final_respondent_id.isin([62])
                ),
                pd.NA,
            ),
        )
        .fillna(
            # assign the rest of SOCO
            df.balancing_authority_code_eia.where(
                df.balancing_authority_code_eia.isin(["SOCO"]),
                pd.NA,
            ),
        )
        .fillna(
            # Aggregate Entergy PS
            pd.Series("ETR", index=df.index).where(
                df.final_respondent_id.isin([100, 315, 454, 8]),
                pd.NA,
            ),
        )
        .fillna(
            # Aggregate Evergy
            pd.Series("EVRG", index=df.index).where(
                df.final_respondent_id.isin([79, 80, 182, 191]),
                pd.NA,
            ),
        )
        .fillna(
            # Aggregate Alliant Energy
            pd.Series("LNT", index=df.index).where(
                df.final_respondent_id.isin([194, 281]),
                pd.NA,
            ),
        )
        .fillna(
            # AEP, combining Appalachian Power Co. and Indiana Michigan Power Co.
            # from PJM into an integrated AEP, based on approximate FRR linked above
            pd.Series("AEP", index=df.index).where(
                df.final_respondent_id.isin([6, 73]),
                pd.NA,
            ),
        )
        .fillna(
            # Aggregate HECO
            pd.Series("HECO", index=df.index).where(
                df.balancing_authority_code_eia.isin(["HECO"])
                | df.final_respondent_id.isin([65, 94, 300])
                | df.state.isin(["HI"]),
                pd.NA,
            ),
        )
        .fillna(
            # Aggregate Alaska
            pd.Series("Alaska", index=df.index).where(
                df.state.isin(["AK"]),
                pd.NA,
            ),
        )
        .fillna(
            # keep safe respondent ids
            df.final_respondent_id.astype(str).where(
                df.final_respondent_id.isin(resps_to_keep),
                pd.NA,
            ),
        )
        .fillna(
            # Aggregate PSCO (must be after respondents b/c basin and tri-state)
            pd.Series("PSCO", index=df.index).where(
                df.balancing_authority_code_eia.isin(["PSCO"])
                | df.final_respondent_id.isin([145]),
                pd.NA,
            ),
        )
        .fillna(
            # apply BA maps / safe codes
            df.balancing_authority_code_eia.replace(ba_replace)
        )
    )
    return df
