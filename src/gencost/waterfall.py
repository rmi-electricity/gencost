import logging
import warnings
from datetime import datetime as dt
from pathlib import Path

import numpy as np
import pandas as pd
import pandera as pa
import seaborn as sns
import plotly.express as px
import plotly.graph_objects as go
from etoolbox.utils.pudl_helpers import (
    month_year_to_date,
    simplify_columns,
    sum_and_weighted_average_agg,
)
from pandera import Check, Column
from platformdirs import user_cache_path, user_documents_path

from gencost.constants import (
    CURRENT_EP_COLS,
    FILL_IN_EP_COLS,
    FOSSIL_PRIME_MOVER_MAP,
    FUEL_GROUP_MAP,
    GET_860_GEN_COLS,
    HIST_EP_COLS,
)
from gencost.crosswalk import Crosswalk
from gencost.entity_ids import add_ba_code
from gencost.package_data import PACKAGE_PATH

from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error, mean_squared_error

pat_path = Path(__file__).parent
CACHE_PATH = user_cache_path("gencost", "rmi")
logger = logging.getLogger(__name__)


def subplants_in_scenario_one(gen_923_by_subplant):
    """Make a list of sub-plant composite key that work in scenario #1,
    so we don't have to try to match them in scenario 2."""
    return (
        gen_923_by_subplant.assign(
            year=lambda x: x.report_date.dt.year,
            plant_subplant_year_eia=lambda x: x[["plant_id_eia", "subplant_id", "year"]]
            .astype(str)
            .agg("_".join, axis=1),
        )
        .plant_subplant_year_eia.unique()
        .tolist()
    )


def mode(x):
    """Custom mode agg func."""
    a = pd.Series(x).mode()
    if len(a) == 0:
        return pd.NA
    if len(a) == 1:
        return a[0]
    else:
        return ", ".join(map(str, a))


def sorted_unique_cat(x):
    """Custom unique cat function."""
    a = sorted(set(x))
    if len(a) == 0:
        return pd.NA
    if len(a) == 1:
        return a[0]
    else:
        return ", ".join(map(str, a))


def fix_cc_in_prime(df, old_col="prime_mover_code"):
    """Add prime_mover call with CCs rolled together."""
    return df.assign(prime_mover=lambda x: x[old_col].replace(FOSSIL_PRIME_MOVER_MAP))


def add_fuel_group(df, old_col="energy_source_code"):
    """Add new column with fuel groups."""
    return df.assign(fuel_group=lambda x: x[old_col].replace(FUEL_GROUP_MAP))


def drop_zero_cols(df, keep=("solid_fuel_gasification",)):
    """Drop numeric columns that sum to zero."""
    non_zeros = df.sum(axis=0, numeric_only=True) != 0
    for col in keep:
        non_zeros.loc[col] = True
    return df.loc[:, [non_zeros.get(x, True) for x in df.columns]]


def _hr(df, by, mmbtu_col, mwh_col):
    """Calculate aggregated heat rate."""
    return df.groupby(by)[mmbtu_col].transform("sum") / df.groupby(by)[
        mwh_col
    ].transform("sum")


def positive_heat_rate(
    df: pd.DataFrame,
    mmbtu_col: str,
    mwh_col: str,
    src: bool = False,
) -> np.ndarray | pd.Series:
    """Find the best non-negative heat rate.

    Args:
        df: input dataframe
        mmbtu_col: name of fuel consumption column to use
        mwh_col: name of generation column to use
        src: if True return source of heat rate rather than data

    Returns: array-like of non-negative heat rates or their source

    """
    hr = df[mmbtu_col] / df[mwh_col]
    avg_ppf_hr = _hr(
        df, ["plant_id_eia", "prime_mover", "fuel_group"], mmbtu_col, mwh_col
    )
    avg_pf_hr = _hr(df, ["prime_mover", "fuel_group"], mmbtu_col, mwh_col)
    avg_p_hr = _hr(df, ["prime_mover"], mmbtu_col, mwh_col)
    if not np.all(avg_p_hr >= 0.0):
        x_ = df.assign(avg_p_hr=avg_p_hr)
        bad = x_[x_.prime_mover.isin(FOSSIL_PRIME_MOVER_MAP.values()) & x_.avg_p_hr < 0]
        if not bad.empty:
            bad = (
                bad.groupby(["prime_mover", "fuel_group"])
                .plant_id_eia.nunique()
                .to_dict()
            )
            raise AssertionError(
                f"Count of plants with negative heat rates in all aggregations:\n{bad}"
            )

    if src:
        return np.where(
            hr > 0.0,
            "no agg",
            np.where(
                avg_ppf_hr > 0.0,
                "plant prime fuel",
                np.where(avg_pf_hr > 0.0, "prime fuel", "prime"),
            ),
        )
    return np.where(
        hr > 0.0,
        hr,
        np.where(
            avg_ppf_hr > 0.0, avg_ppf_hr, np.where(avg_pf_hr > 0.0, avg_pf_hr, avg_p_hr)
        ),
    )


def bio_into_other(df, col_suffix):
    """Filter with columns suffix and combine biofuel into other."""
    filter_cols = list(df.filter(like=col_suffix).columns)
    if len(filter_cols) == 0:
        raise ValueError(
            f"Cannot combine biofuel into other, no columns with {col_suffix=}"
        )
    filtered = df[filter_cols]
    filtered["other" + col_suffix] = (
        filtered["other" + col_suffix] + filtered["biofuel" + col_suffix]
    )
    return filtered.drop(columns=["biofuel" + col_suffix])


def allocate_col_by(
    df: pd.DataFrame,
    *,
    to_allocate: str,
    new_suffix: str,
    old_suffix: str,
    fillna: int | float | str | None = None,
    rollup_by: list | None = None,
    drop: bool = True,
    drop_bad_rows: str | None = None,
):
    """Allocate a column proportionally using values in a set of columns.

    Args:
        df: input dataframe
        to_allocate: the column that will be allocated
        new_suffix: suffix that will replace the old one in the new columns
        old_suffix: suffix of columns to use for allocation
        fillna: fill nans in new columns with new value
        rollup_by: columns to use in groupby, this rollup is used for allocations
            when a given row has only nans and more than one zero.
        drop: drop the old_suffix columns
        drop_bad_rows: drop rows where the allocation failed, rows are dropped if
            argument is not None, pass a string to insert into log message

    Returns:

    """
    old_cols = list(df.filter(like=old_suffix).columns)
    new_cols = [x.replace(old_suffix, new_suffix) for x in old_cols]
    if rollup_by is not None:
        agg_old_cols = df.groupby(rollup_by)[old_cols].transform("sum")
        multi_zeros = agg_old_cols.divide(agg_old_cols.sum(axis=1), axis=0)
    else:
        multi_zeros = 0.0
    df[new_cols] = np.multiply(
        np.where(
            # this checks where row sums to zero, have to do this at the row level to
            # make sure allocation is consistent across row
            np.repeat(df[old_cols].sum(axis=1)[:, np.newaxis], len(old_cols), 1) != 0.0,
            df[old_cols].divide(df[old_cols].sum(axis=1), axis=0),
            np.where(
                # all columns nan except one that is zero, zero col gets 100% allocation
                np.repeat(
                    df[old_cols].isna().sum(axis=1)[:, np.newaxis], len(old_cols), 1
                )
                == len(old_cols) - 1,
                # if only one zero, zero col gets 100% allocation
                np.where(df[old_cols] == 0.0, 1.0, np.nan),
                # otherwise use allocation based on all years of data
                multi_zeros,
            ),
        ),
        df[to_allocate][:, np.newaxis],
    )
    if fillna is not None:
        df[new_cols] = df[new_cols].fillna(fillna)
    if drop_bad_rows is not None:
        close = np.isclose(df[to_allocate], df[new_cols].sum(axis=1), rtol=1e-2)
        if (num := np.sum(~close)) > 0:
            logger.warning(
                "%s: dropping %s rows because %s allocation by %s failed.",
                drop_bad_rows,
                num,
                to_allocate,
                old_suffix,
            )
            df = df[close]
    if drop:
        return df.drop(columns=old_cols)
    return df


def get_predicted_gross_gen(df, xwalk):
    """
    get predicted values from multivariate regression

    Args:
        df (pd.Dataframe): input df with historical net and gross values
        xwalk (pd.Dataframe): df with xwalk from subplant to generator

    Output:
        default: epd dataframe with new predicted gross gen values

    """
    # add tech description to epd
    gtn = df.query("technology_description.notna() & gross_generation_mwh.notna()")

    # make list of techs for for loop
    technology_descriptions = gtn["technology_description"].unique().tolist()

    # empty list for dfs
    filled_in = []

    for tech in technology_descriptions:
        # regression
        # test data
        y = gtn.query("technology_description == @tech")["gross_generation_mwh"]
        X = gtn.query("technology_description == @tech")[
            [
                "net_generation_mwh",
                "capacity_mw",
                "age_of_observation",
                "age_in_report_year",
            ]
        ]

        # train the linear regression
        regressor = LinearRegression()
        regressor.fit(X, y)

        # make predictions on test data
        y_pred = regressor.predict(X)
        # add cols on regression stats to df
        gtn_w_predict = (
            gtn.query("technology_description == @tech")
            .assign(
                intercept=lambda x: regressor.intercept_,
                net_gen_coefficient=lambda x: regressor.coef_[0],
                capacity_coefficient=lambda x: regressor.coef_[1],
                age_obs_coefficient=regressor.coef_[2],
                age_report_coefficient=regressor.coef_[3],
            )[
                [
                    "plant_id_eia",
                    "report_date",
                    "subplant_id",
                    "intercept",
                    "net_gen_coefficient",
                    "capacity_coefficient",
                    "age_obs_coefficient",
                    "age_report_coefficient",
                ]
            ]
            .merge(
                xwalk.drop_duplicates(
                    subset=["plant_id_eia", "generator_id", "subplant_id"]
                )[["plant_id_eia", "generator_id", "subplant_id"]],
                on=["plant_id_eia", "subplant_id"],
                how="left",
            )
        )

        filled_in.append(gtn_w_predict)

    # combine lists for each tech
    return pd.concat(filled_in)


def rime_sort_key(string: str):
    """Sort strings starting from the end."""
    return string[::-1]


class DataBySubplant:
    def __init__(
        self,
        crosswalk: Crosswalk,
    ):
        """

        Args:
            crosswalk: :class:`patio.plant_prime_networkx.Crosswalk`.
        """
        if isinstance(crosswalk, Crosswalk):
            self._xwalk = crosswalk
        else:
            raise TypeError(
                f"crosswalk must be `Crosswalk` object, not {type(crosswalk)}"
            )
        self._dfs = {}

    @property
    def xwalk(self):
        return self._xwalk.grand_crosswalk

    @property
    def safe_xwalk(self):
        return self._xwalk.safe_xwalk.copy()

    @property
    def pudl_tabl(self):
        return self._xwalk.pudl_tabl

    def query(self, expr):
        """Return all years and subplants related to the subplant/years
        that satisfy query."""
        if "@" in expr:
            raise RuntimeError("@ syntax does not work.")
        self.merge_all().query(expr).plant_id_eia.unique()
        return self.merge_all().query("plant_id_eia in @q")

    def clear(self):
        """Remove cached data so it can be recalculated."""
        self._dfs = {}

    def get_cems(self):
        if "raw_cems" not in self._dfs:
            self._dfs["raw_cems"] = pd.read_parquet(
                PACKAGE_PATH / "camd_unit_starts_ms.parquet.gzip"
            ).rename(
                columns={
                    "plant_id_cems": "plant_id_epa",
                    "unit_id_cems": "emissions_unit_id_epa",
                    "gross_gen": "gross_generation_mwh",
                    "gross_gen_max": "camd_capacity_mw",
                    "gen_starts": "generator_starts",
                }
            )
        return self._dfs["raw_cems"].copy()

    ###########################################################################
    # Integrate data sources
    ###########################################################################

    def merge_all(self, clean=True, rollup=False):
        if "merge_all" not in self._dfs:
            exa = self.get_exa_all().pipe(self.add_costs, on="pf_subplant_id")

            if rollup:
                aggs = {
                    "step": "first",
                    "generator_starts": "sum",  # max?
                    "fuel_starts": "sum",  # max?
                    "subplant_id": pd.Series.unique,
                }
                index_cols = ["plant_id_eia", "pf_subplant_id", "report_date"]
                # aggregate all waterfall levels to prime for merging with cost
                out = exa.groupby(index_cols).agg(
                    {col: aggs.get(col, "sum") for col in exa if col not in index_cols}
                )
            else:
                out = exa

            test = (
                out.query("ferc_merge != 'both'")
                .replace({"ferc_merge": {"left_only": "exa", "right_only": "ferc"}})
                .groupby(["ferc_merge", "prime_mover"])
                .plant_id_eia.nunique()
                .to_frame()
                .query("plant_id_eia > 0")
                .squeeze()
            )
            logger.warning(
                "Final merge stats, only those marked 'all' will be retained "
                ":\n %s \n",
                test.squeeze().to_dict(),
            )
            print(test.squeeze().to_dict())
            gross_mwh_cols = out.filter(like="_gross_mwh").columns
            out = out.query("ferc_merge == 'both'").assign(
                hrs_in_yr=lambda x: np.where(x.report_date.dt.is_leap_year, 8784, 8760),
                net_cf=lambda x: x.net_generation_mwh / (x.capacity_mw * x.hrs_in_yr),
                gross_cf=lambda x: x.gross_generation_mwh
                / (x.capacity_mw * x.hrs_in_yr),
                gross_hr=lambda x: x.heat_in_mmbtu / x.gross_generation_mwh,
                parasitic_load_pct=lambda x: (
                    x.gross_generation_mwh - x.net_generation_mwh
                )
                / (x.capacity_mw * x.hrs_in_yr),
                n_fuel_groups=lambda x: (
                    x[gross_mwh_cols] / x[gross_mwh_cols].sum(axis=1)
                )
                .gt(0.02)
                .sum(axis=1)
                .astype("Int64"),
                top_fuel_share=lambda x: bio_into_other(x, "_gross_mwh").max(axis=1)
                / x[gross_mwh_cols].sum(axis=1),
                top_fuel=lambda x: bio_into_other(x, "_gross_mwh")
                .fillna(0.0)
                .idxmax(axis=1)
                .str.replace("_gross_mwh", ""),
                true_multi_fuel="multi_fuel",
                fuel_category=lambda x: x.true_multi_fuel.mask(
                    x.top_fuel_share >= 0.6,
                    "≥60% " + x.top_fuel,
                ).mask(x.top_fuel_share >= 0.9, x.top_fuel),
                report_year=lambda x: x.report_date.dt.year,
                real_pollution_control_costs_per_kw=lambda x: x.pollution_control_costs_per_kw
                * x.inflator_to_2021,
            )

            out[[c.replace("_gross_mwh", "_fraction") for c in gross_mwh_cols]] = (
                out[gross_mwh_cols]
                .divide(out[gross_mwh_cols].sum(axis=1), axis=0)
                .fillna(0.0)
            )
            out[[c.replace("_gross_mwh", "_gross_cf") for c in gross_mwh_cols]] = (
                out[gross_mwh_cols]
                .divide(out.capacity_mw * out.hrs_in_yr, axis=0)
                .fillna(0.0)
            )
            core_fuels = ["coal_fraction", "natural_gas_fraction", "petroleum_fraction"]
            out = out.assign(
                minor_fuels_fraction=lambda x: x.filter(like="_fraction").sum(axis=1)
                - x[core_fuels].sum(axis=1)
            )

            # add core validation step

            # validate merge all specifics
            self._dfs["merge_all"] = self.core_validation(
                out.drop(columns=["ferc_merge", "hrs_in_yr", "true_multi_fuel"]),
                level="subplant",
            )

            if clean:
                return (
                    self._dfs["merge_all"]
                    .astype({"parasitic_load_pct": float, "gross_cf": float})
                    .query("0.0 < parasitic_load_pct < 0.2 & 0.0 <= gross_cf <= 1.5")
                    .astype({"parasitic_load_pct": "Float64", "gross_cf": "Float64"})
                    .copy()
                )

        return self._dfs["merge_all"]

    def get_eternally_present_by_generator(self):
        """
        Objective: combine historical and counterfactual dataframes

        Process:

        Notes:
        Three types of counterfactuals
        1) missing years
        2) fuel switch
        3) zeroes reported

        For instances a generator switched fuel or
        reported zero fuel consumption or generation,
        the counterfactual observation replaces the
        historical one

        """

        historical = self.get_historical_by_generator().assign(
            type=lambda x: "historical",
            mmbtu=lambda x: x.filter(like="_fraction").sum(axis=1),
        )
        # take out where mmbtu and net gen are zero, for cf to replace
        historical_clean = historical.loc[
            ~((historical["mmbtu"] == 0) & (historical["net_generation_mwh"] == 0))
        ]

        cf = self.fill_in_ep_data().assign(type=lambda x: "counterfactual")

        """only plant / gen / year duplicates at this stage are
            for fuel switches,  so let's keep counterfactual observation
            by keeping last row appeared in duplicates
            """
        return (
            pd.concat([historical_clean, cf])
            .drop(columns=["mmbtu"])
            .drop_duplicates(
                subset=["plant_id_eia", "generator_id", "report_date"], keep="last"
            )
        )

    def get_historical_by_generator(self):
        if "exa_by_gen" not in self._dfs:
            df_860 = self.get_860_by_x(subplant_id_col="generator_id")
            df_923 = self.get_gf923_by_generator()
            df_cems = self.get_cems_by_generator()

            # merge cems and 923 for gen-fuel level allocation of gross gen
            df = pd.merge(
                df_923,
                df_cems,
                on=["plant_id_eia", "generator_id", "report_date"],
                how="outer",
                validate="1:1",
                indicator="cems_923_merge",
            )
            # allocate cems gross gen using pivoted gf 923
            cems_and_923 = allocate_col_by(
                df,
                to_allocate="gross_generation_mwh",
                new_suffix="_gross_mwh",
                old_suffix="_mmbtu",
                rollup_by=["plant_id_eia", "generator_id"],
                drop=False,
            )

            cems_and_923 = drop_zero_cols(cems_and_923)

            merged = (
                cems_and_923.merge(
                    df_860,
                    on=["plant_id_eia", "generator_id", "report_date"],
                    validate="1:1",
                    how="outer",
                    indicator="exa_merge",
                )
                .assign(
                    _merge=lambda x: x[["cems_923_merge", "exa_merge"]]
                    .astype("string")
                    .fillna("")
                    .agg(",".join, axis=1)
                    .replace(
                        {
                            "both,both": "all",
                            "both,left_only": "cems_923_only",
                            "right_only,both": "exa_860",
                        }
                    )
                )
                .drop(columns=["cems_923_merge", "exa_merge"])
                .merge(
                    self.get_wage_scale(),
                    on=["report_date", "state"],
                    how="left",
                    validate="m:1",
                )
                .fillna({"wage_scale": 1})
                .assign(
                    hrs_in_yr=lambda x: np.where(
                        x.report_date.dt.is_leap_year, 8784, 8760
                    ),
                    gross_cf=lambda x: x.gross_generation_mwh
                    / (x.capacity_mw * x.hrs_in_yr),
                )
                .merge(
                    pd.read_parquet(
                        PACKAGE_PATH
                        / "860_FERC_matching_cost_regressions.parquet.gzip",
                    )[["report_year", "inflator_to_2021"]]
                    .drop_duplicates()
                    .assign(
                        report_date=lambda x: pd.to_datetime(
                            x["report_year"], format="%Y"
                        )
                    ),
                    on=["report_date"],
                    how="left",
                )
                .assign(
                    real_pollution_control_costs_per_kw=lambda x: x.pollution_control_costs_per_kw
                    * x.inflator_to_2021
                )  # pandera caught 3 observations w/null prime movers
                .query("prime_mover.notnull()")
                .query("prime_mover in @FOSSIL_PRIME_MOVER_MAP")
            )

            new = (
                merged.merge(
                    get_predicted_gross_gen(self.get_exa_by_subplant(), self.xwalk),
                    on=["plant_id_eia", "report_date", "generator_id"],
                    how="left",
                )
                .assign(
                    predicted_gross_gen_mwh=lambda x: x["net_generation_mwh"]
                    * x["net_gen_coefficient"]
                    + x["capacity_mw"] * x["capacity_coefficient"]
                    + x["age_of_observation"] * x["age_obs_coefficient"]
                    + x["age_in_report_year"] * x["age_report_coefficient"]
                    + x["intercept"],
                    gross_gen_value=lambda x: np.where(
                        (x["gross_cf"] > 1.5)
                        | (
                            (x["gross_generation_mwh"] == 0)
                            & abs(x["net_generation_mwh"])
                            > 0
                        ),
                        "predicted",
                        "reported",
                    ),
                    gross_generation_mwh=lambda x: np.where(
                        (x["gross_cf"] > 1.5)
                        | (
                            (x["gross_generation_mwh"] == 0)
                            & abs(x["net_generation_mwh"])
                            > 0
                        ),
                        x["predicted_gross_gen_mwh"],
                        x["gross_generation_mwh"],
                    ),
                    gross_cf=lambda x: x.gross_generation_mwh
                    / (x.capacity_mw * x.hrs_in_yr),
                )
                .drop(columns="predicted_gross_gen_mwh")
            )

            # fuel fraction calcs from merge all
            gross_mwh_cols = new.filter(like="_gross_mwh").columns

            new[[c.replace("_gross_mwh", "_fraction") for c in gross_mwh_cols]] = (
                new[gross_mwh_cols]
                .divide(new[gross_mwh_cols].sum(axis=1), axis=0)
                .fillna(0.0)
            )

            core_fuels = ["coal_fraction", "natural_gas_fraction", "petroleum_fraction"]

            out = (
                new.assign(
                    minor_fuels_fraction=lambda x: x.filter(like="_fraction").sum(
                        axis=1
                    )
                    - x[core_fuels].sum(axis=1)
                )
                .query('_merge == "all"')
                .drop(columns=["_merge", "hrs_in_yr"])
                .query(
                    "gross_generation_mwh.notna()"
                )  # only 2 generators, mismatch in subset
            )

            self._dfs["exa_by_gen"] = self.core_validation(out, level="generator")

        return self._dfs["exa_by_gen"].copy()

    def get_exa_all(self, by_fuel=True):
        """
        Args:
        pf_crosswalk (dataframe): crosswalk with prime fuel from crosswalk class
        crosswalk (dataframe): grand crosswalk from crosswalk class
        pudl_out : class for extracting pudl data

        Put all data together for complete waterfall output. The shapes of each step in
        the waterfall are different, so merges cannot be done in one sweep.

        Steps:
        1) Complete waterfall step 1 by merging BF df to G 923 df
        2) Concat waterfall step 1 and 2 into single df
        3) Merge cems and 860 data in
        4) filter based on ppf totals - throw out everything that matches with PPF
            except ST's
        5) concat to ppf for all eia_cems_merge data


        """
        waterfall = self.get_exa_by_subplant(by_fuel=by_fuel).merge(
            self.xwalk[
                ["plant_id_eia", "subplant_id", "pf_subplant_id"]
            ].drop_duplicates(),
            on=["plant_id_eia", "subplant_id"],
            how="left",
            validate="m:1",
        )

        # filter wf based on ppf totals
        ppf = self.get_exa_by_prime().assign(step=3)

        # merge ppf df in to compare
        # capacity match columns
        # bring in prime mover from crosswalk (single prime subplants only)
        # concat ids for later filtering
        # ST check for filtering

        comparison = (
            # aggregate waterfall steps 1 and 2 data to pf_subplant
            waterfall.groupby(["plant_id_eia", "pf_subplant_id", "report_date"])[
                [
                    "capacity_mw",
                    "net_generation_mwh",
                ]
            ]
            .sum()
            .reset_index()
            # merge in ppf data for comparison
            .merge(
                ppf,
                on=["plant_id_eia", "pf_subplant_id", "report_date"],
                how="outer",
                validate="1:1",
                suffixes=("_waterfall", "_ppf"),
                indicator=True,
            )
            # check data matches
            .assign(
                capacity_match=lambda x: np.isclose(
                    x.capacity_mw_waterfall, x.capacity_mw_ppf, rtol=0.1
                ),
            )
        )
        from_water = comparison.query(
            "(capacity_match & _merge == 'both') | _merge == 'left_only'"
        )
        from_ppf = comparison.query(
            "(~capacity_match & _merge == 'both') | _merge == 'right_only'"
        )

        filtered_ppf = ppf.merge(
            from_ppf[["plant_id_eia", "pf_subplant_id", "report_date"]],
            on=["plant_id_eia", "pf_subplant_id", "report_date"],
            how="inner",
            validate="1:1",
        )
        filtered_water = waterfall.merge(
            from_water[["plant_id_eia", "pf_subplant_id", "report_date"]],
            on=["plant_id_eia", "pf_subplant_id", "report_date"],
            how="inner",
            validate="m:1",
        )

        # now that both waterfall and ppf have been filtered, let's concat them
        ppf_and_waterfall = (
            pd.concat([filtered_water, filtered_ppf])
            .sort_values(
                by=["plant_id_eia", "pf_subplant_id", "subplant_id", "report_date"]
            )
            .reset_index(drop=True)
        )

        types = {
            "plant_id_eia": "Int64",
            "pf_subplant_id": "Int64",
            "subplant_id": "Int64",
            "report_date": "datetime64[ns]",
            "step": "Int64",
            "capacity_mw": "float64",
            "camd_capacity_mw": "float64",
            "net_generation_mwh": "float64",
            "generator_starts": "Int64",
            "fuel_starts": "Int64",
            "gross_generation_mwh": "float64",
            "heat_in_mmbtu": "float64",
        }
        return ppf_and_waterfall.astype(types)[
            list(types) + [x for x in ppf_and_waterfall if x not in types]
        ]

    def get_exa_by_prime(self):
        if "exa_by_prime" not in self._dfs:
            df_923 = self.get_gf923_by_prime()
            # cems data aggregated to ppf_subplant id
            df_cems = self.get_cems_by_x(subplant_id_col="pf_subplant_id")
            df_860 = self.get_860_by_x(subplant_id_col="pf_subplant_id")
            merged0 = df_860.merge(
                df_923,
                on=["plant_id_eia", "pf_subplant_id", "report_date"],
                validate="1:1",
                how="right",
                indicator="eia_merge",
            )
            merged = (
                merged0.merge(
                    df_cems,
                    on=["plant_id_eia", "pf_subplant_id", "report_date"],
                    validate="1:1",
                    how="left",
                    indicator="exa_merge",
                )
                .sort_values(["plant_id_eia", "pf_subplant_id", "report_date"])
                .assign(
                    cum_starts=lambda x: x.groupby(
                        ["plant_id_eia", "pf_subplant_id"]
                    ).generator_starts.transform("cumsum"),
                    _merge=lambda x: x[["eia_merge", "exa_merge"]]
                    .astype("string")
                    .fillna("")
                    .agg(",".join, axis=1)
                    .replace(
                        {
                            "both,both": "all",
                            "both,left_only": "eia_only",
                            "right_only,both": "923_epa",
                        }
                    ),
                )
                .drop(columns=["eia_merge", "exa_merge"])
            )

            test = merged.groupby("_merge").plant_id_eia.nunique()
            logger.warning(
                "EXA by prime: only those marked 'all' will be retained :\n %s \n",
                test.squeeze().to_dict(),
            )
            out = (
                merged.query("_merge == 'all'")
                .drop(columns=["_merge"])
                .dropna(axis=1, how="all")
            )
            # bf_gross_mwh columns are not true gross generation, they are really
            # calculated
            out = allocate_col_by(
                out,
                to_allocate="gross_generation_mwh",
                new_suffix="_gross_mwh",
                old_suffix="_bf_gross_mwh",
                drop=True,
                drop_bad_rows="Waterfall step three",
                rollup_by=["plant_id_eia", "pf_subplant_id"],
            )
            self._dfs["exa_by_prime"] = drop_zero_cols(out)
        return self._dfs["exa_by_prime"]

    def get_exa_by_subplant(self, by_fuel=True):
        """
        1) Complete waterfall step 1 by merging BF df to G 923 df
        2) Concat waterfall step 1 and 2 into single df
        3) Merge cems and 860 data in

        Returns:

        """
        if not by_fuel:
            raise RuntimeError("by_fuel is no longer used, it is always True")
        if "waterfall" not in self._dfs:
            # for both waterfall subsets
            df_860 = self.get_860_by_x(subplant_id_col="subplant_id")
            df_cems = self.get_cems_by_x(subplant_id_col="subplant_id")

            # waterfall step 1:
            df_gen923 = self.get_gen923_by_subplant()
            df_bf923 = self.get_bf923_by_subplant()

            # add fuel consumption data to make waterfall step one complete
            wf1 = df_gen923.merge(
                df_bf923,
                on=["plant_id_eia", "subplant_id", "report_date"],
                how="inner",
                validate="1:1",
            )

            # create net_mwh by fuel columns
            wf1 = allocate_col_by(
                wf1,
                to_allocate="net_generation_mwh",
                new_suffix="_net_mwh",
                old_suffix="_bf_net_mwh",
                drop=True,
                drop_bad_rows="Waterfall step one",
                rollup_by=["plant_id_eia", "subplant_id"],
            )
            # waterfall step 2:
            wf2 = self.get_gf923_by_subplant(
                # crosswalk with prime fuel from crosswalk class, used OGE version so
                # preserving that for now
                subplants_in_scenario_one(wf1),
            )

            # now that both waterfall steps have generation and fuel consumption,
            # let's concat them
            waterfall = pd.concat([wf1.assign(step=1), wf2.assign(step=2)]).sort_values(
                by=["plant_id_eia", "subplant_id", "report_date"]
            )

            # merge cems and 860 data
            merged = (
                df_860.merge(
                    waterfall,
                    on=["plant_id_eia", "subplant_id", "report_date"],
                    validate="1:1",
                    how="right",
                    indicator="eia_merge",
                )
                .merge(
                    df_cems,
                    on=["plant_id_eia", "subplant_id", "report_date"],
                    validate="1:1",
                    how="outer",
                    indicator="exa_merge",
                )
                .sort_values(["plant_id_eia", "subplant_id", "report_date"])
                .assign(
                    cum_starts=lambda x: x.groupby(
                        ["plant_id_eia", "subplant_id"]
                    ).generator_starts.transform("cumsum"),
                    _merge=lambda x: x[["eia_merge", "exa_merge"]]
                    .astype("string")
                    .fillna("")
                    .agg(",".join, axis=1)
                    .replace(
                        {
                            "both,both": "all",
                            "both,left_only": "eia_only",
                            "right_only,left_only": "waterfall_only",
                            "right_only,both": "waterfall_epa",
                            ",right_only": "epa_only",
                        }
                    ),
                )
                .drop(columns=["exa_merge", "eia_merge"])
            )
            test = merged.groupby("_merge").plant_id_eia.nunique()
            logger.warning(
                "Final merge stats, only those marked 'all' will be retained from "
                "waterfall 1 and 2:\n %s \n",
                test.squeeze().to_dict(),
            )
            # bf_gross_mwh columns are not true gross generation, they are really
            # calculated from fuel consumption and never negative HRs, but those are
            # net HRs
            merged = allocate_col_by(
                merged.query("_merge == 'all'").drop(columns=["_merge"]),
                to_allocate="gross_generation_mwh",
                new_suffix="_gross_mwh",
                old_suffix="_bf_gross_mwh",
                drop=True,
                drop_bad_rows="Waterfall steps one+two",
                rollup_by=["plant_id_eia", "subplant_id"],
            )

            merged = drop_zero_cols(merged)
            self._dfs["waterfall"] = merged
        return self._dfs["waterfall"]

    def export_data_by_prime(self, name=None, clean=True):
        name = "data_for_pf_subplants.parquet" if name is None else name
        self.merge_all(clean=clean).to_parquet(user_documents_path() / name)

    ###########################################################################
    # Check distribution of metrics
    ###########################################################################

    @property
    def parasitic_load_distribution(self):
        return (
            pd.value_counts(
                pd.cut(
                    self.merge_all().parasitic_load_pct,
                    [-1e4, -100, -5, -1, 0, 1, 5, 100, 1e4],
                )
            ).sort_index()
            / self.merge_all().parasitic_load_pct.count()
        )

    @property
    def gross_cf_distribution(self):
        return (
            pd.value_counts(
                pd.cut(
                    self.merge_all().gross_cf,
                    [-5, -1, -0.5, 0, 0.5, 1, 1.2, 5, 10],
                )
            ).sort_index()
            / self.merge_all().gross_cf.count()
        )

    @property
    def net_cf_distribution(self):
        return (
            pd.value_counts(
                pd.cut(
                    self.merge_all().net_cf,
                    [-5, -1, -0.5, 0, 0.5, 1, 1.2, 5, 10],
                )
            ).sort_index()
            / self.merge_all().net_cf.count()
        )

    @property
    def covered_generators(self):
        return self.safe_xwalk.copy().merge(
            self.merge_all()
            .copy()[["plant_id_eia", "pf_subplant_id"]]
            .drop_duplicates(),
            on=["plant_id_eia", "pf_subplant_id"],
            how="inner",
            validate="m:1",
        )

    ###########################################################################
    # Figure drawing methods
    ###########################################################################

    @property
    def yr_groups(self):
        return {
            yr: f"{first}-{last}"
            for yr in range(2008, 2021)
            for first, last in [(2008, 2012), (2013, 2015), (2016, 2020)]
            if first <= yr <= last
        }

    def draw_cems_eia_scatter(
        self,
        comparison,
        facet_col=None,
        facet_row=None,
        color=None,
        height=500,
        width=500,
        clean=True,
    ) -> go.Figure:
        result = (
            self.merge_all(clean=clean)
            .query("report_date > 2007 & report_date < 2021")
            .assign(year_group=lambda x: x.report_date.dt.year.replace(self.yr_groups))
        )
        auto = {
            "capacity": {"x": "capacity_mw", "y": "camd_capacity_mw"},
            "capacity_ferc": {
                "x": "capacity_mw",
                "y": "capacity_of_currently_operating_units",
            },
            "energy": {"x": "net_generation_mwh", "y": "gross_generation_mwh"},
            "cf": {"x": "net_cf", "y": "gross_cf"},
            "cf_ferc": {"x": "net_cf", "y": "ferc_cf"},
        }
        if isinstance(comparison, str) and comparison in auto:
            comparison = auto[comparison]
        if any(("x" not in comparison, "y" not in comparison)):
            raise ValueError(
                f"'comparison' must be one of {tuple(auto.keys())} or a dict with "
                f"keys 'x' and 'y' each of which is one of the following "
                f"cols: \n {tuple(result.columns)}"
            )

        fig = px.scatter(
            result.astype({k: float for k in comparison.values()}),
            **comparison,
            facet_col=facet_col,
            facet_row=facet_row,
            color=color,
            height=height,
            width=width,
        ).for_each_annotation(lambda a: a.update(text=a.text.split("=")[-1]))
        return fig

    def draw_ecdf(
        self,
        x="net_cf",
        color="prime_mover",
        facet_col=None,
        facet_row=None,
        marginal="rug",
        clean=True,
        query=None,
        height=None,
        width=None,
    ):
        df = self.merge_all(clean=clean).assign(
            year_group=lambda x: x.report_date.dt.year.replace(self.yr_groups)
        )
        if query is not None:
            df = df.query(query)

        return px.ecdf(
            df,
            x=x,
            markers=True,
            color=color,
            facet_col=facet_col,
            facet_row=facet_row,
            marginal=marginal,
            height=height,
            width=width,
        )

    def draw_capacity_ecdf(
        self,
        facet_col="prime_mover",
        facet_row=None,
        clean=True,
        ecdfnorm="probability",
        ecdfmode="standard",
        height=None,
        width=None,
    ) -> go.Figure:
        result = self.compare_capacity_df(clean=clean).assign(
            year_group=lambda x: x.year.replace(self.yr_groups)
        )
        fig = (
            px.ecdf(
                result.query("year > 2007 & year < 2021"),
                x="capacity_mw",
                facet_col=facet_col,
                facet_row=facet_row,
                color="series",
                ecdfnorm=ecdfnorm,
                ecdfmode=ecdfmode,
                height=height,
                width=width,
            )
            .for_each_annotation(lambda a: a.update(text=a.text.split("=")[-1]))
            .update_yaxes(matches=None, showticklabels=True)
            .update_xaxes(matches=None, showticklabels=True)
        )
        return fig

    def draw_capacity_histogram(
        self,
        facet_col="prime_mover",
        facet_row=None,
        clean=True,
        ecdfnorm="probability",
        ecdfmode="standard",
        height=None,
        width=None,
        query=None,
    ) -> go.Figure:
        result = self.compare_capacity_df(clean=clean).assign(
            year_group=lambda x: x.year.replace(self.yr_groups)
        )
        if query is not None:
            result = result.query(query)
        fig = (
            px.histogram(
                result.query("year > 2007 & year < 2021"),
                x="capacity_mw",
                facet_col=facet_col,
                facet_row=facet_row,
                color="series",
                height=height,
                width=width,
                barmode="overlay",
            )
            .for_each_annotation(lambda a: a.update(text=a.text.split("=")[-1]))
            .update_yaxes(matches=None, showticklabels=True)
            .update_xaxes(matches=None, showticklabels=True)
        )
        return fig

    ###########################################################################
    # Post-integration analysis methods
    ###########################################################################

    def compare_capacity_df(self, clean) -> pd.DataFrame:
        df860 = (
            self.pudl_tabl.gens_eia860()
            .query(
                "operational_status == 'existing' "
                "& prime_mover_code in @FOSSIL_PRIME_MOVER_MAP"
            )
            .copy()
            .pipe(fix_cc_in_prime)
            .assign(year=lambda x: x.report_date.dt.year)[
                [
                    "plant_id_eia",
                    "generator_id",
                    "year",
                    "prime_mover",
                    "capacity_mw",
                    "report_date",
                ]
            ]
        )
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            cems = (
                self.get_cems()
                .assign(year=lambda x: x.report_date.dt.year)
                .merge(
                    self.xwalk.dropna(
                        axis=0, subset=["plant_id_epa", "emissions_unit_id_epa"]
                    ),
                    on=["plant_id_epa", "emissions_unit_id_epa"],
                    how="inner",
                    validate="m:m",
                )[["plant_id_eia", "generator_id", "year"]]
                .drop_duplicates()
            )
        cems_covered = df860.merge(
            cems,
            on=["plant_id_eia", "generator_id", "year"],
            how="inner",
            validate="1:1",
        ).assign(series="camd_matched")

        ferc_matched = (
            self.add_costs(df860, on="prime_mover")
            .query("ferc_merge == 'both'")
            .assign(series="ferc_matched")
        )
        cems_ferc = (
            self.add_costs(cems_covered, on="prime_mover")
            .query("ferc_merge == 'both'")
            .assign(series="camd_ferc")
        )

        df860.merge(
            self.xwalk.merge(
                self.get_exa_by_prime()
                .assign(year=lambda x: x.report_date.dt.year)[
                    ["plant_id_eia", "pf_subplant_id", "year"]
                ]
                .drop_duplicates(),
                on=["plant_id_eia", "pf_subplant_id"],
                how="inner",
                validate="m:m",
            )[["plant_id_eia", "generator_id", "year"]].drop_duplicates(),
            on=["plant_id_eia", "generator_id", "year"],
            how="inner",
            validate="1:1",
        ).assign(series="exa_prime")

        df860.merge(
            self.xwalk.merge(
                self.get_exa_by_subplant()
                .assign(year=lambda x: x.report_date.dt.year)[
                    ["plant_id_eia", "subplant_id", "year"]
                ]
                .drop_duplicates(),
                on=["plant_id_eia", "subplant_id"],
                how="inner",
                validate="m:m",
            )[["plant_id_eia", "generator_id", "year"]].drop_duplicates(),
            on=["plant_id_eia", "generator_id", "year"],
            how="inner",
            validate="1:1",
        ).assign(series="exa_subplant")

        exa_all = df860.merge(
            self.xwalk.merge(
                self.get_exa_all()
                .assign(year=lambda x: x.report_date.dt.year)[
                    ["plant_id_eia", "pf_subplant_id", "year"]
                ]
                .drop_duplicates(),
                on=["plant_id_eia", "pf_subplant_id"],
                how="inner",
                validate="m:m",
            )[["plant_id_eia", "generator_id", "year"]].drop_duplicates(),
            on=["plant_id_eia", "generator_id", "year"],
            how="inner",
            validate="1:1",
        ).assign(series="exa_all")

        ppf_covered = df860.merge(
            self.xwalk.merge(
                self.merge_all(clean=False)
                .assign(year=lambda x: x.report_date.dt.year)[
                    ["plant_id_eia", "pf_subplant_id", "year"]
                ]
                .drop_duplicates(),
                on=["plant_id_eia", "pf_subplant_id"],
                how="inner",
                validate="m:m",
            )[["plant_id_eia", "generator_id", "year"]].drop_duplicates(),
            on=["plant_id_eia", "generator_id", "year"],
            how="inner",
            validate="1:1",
        ).assign(series="final_merge")
        ppf_clean = df860.merge(
            self.xwalk.merge(
                self.merge_all(clean=True)
                .assign(year=lambda x: x.report_date.dt.year)[
                    ["plant_id_eia", "pf_subplant_id", "year"]
                ]
                .drop_duplicates(),
                on=["plant_id_eia", "pf_subplant_id"],
                how="inner",
                validate="m:m",
            )[["plant_id_eia", "generator_id", "year"]].drop_duplicates(),
            on=["plant_id_eia", "generator_id", "year"],
            how="inner",
            validate="1:1",
        ).assign(series="cleaned")

        (
            cems_ferc.merge(
                exa_all,
                on=["plant_id_eia", "generator_id", "year"],
                how="outer",
                indicator="cf_exa",
                validate="1:1",
                suffixes=("_cf", "_exa"),
            )
            .merge(
                ppf_covered,
                on=["plant_id_eia", "generator_id", "year"],
                how="outer",
                indicator="final",
                validate="1:1",
                suffixes=("_cfa", "_fin"),
            )
            .sort_values(["plant_id_eia", "generator_id", "year"])
        )

        result = pd.concat(
            [
                # df860.assign(series="860").drop_duplicates(
                #     subset=["plant_id_eia", "generator_id", "year"]
                # ),
                cems_covered.drop_duplicates(
                    subset=["plant_id_eia", "generator_id", "year"]
                ),
                ferc_matched.drop_duplicates(
                    subset=["plant_id_eia", "generator_id", "year"]
                ),
                cems_ferc.drop_duplicates(
                    subset=["plant_id_eia", "generator_id", "year"]
                ),
                # exa_prime.drop_duplicates(
                #     subset=["plant_id_eia", "generator_id", "year"]
                # ),
                # exa_subplant.drop_duplicates(
                #     subset=["plant_id_eia", "generator_id", "year"]
                # ),
                exa_all.drop_duplicates(
                    subset=["plant_id_eia", "generator_id", "year"]
                ),
                ppf_covered.drop_duplicates(
                    subset=["plant_id_eia", "generator_id", "year"]
                ),
                ppf_clean.drop_duplicates(
                    subset=["plant_id_eia", "generator_id", "year"]
                ),
            ]
        )
        return result

    ###########################################################################
    # Aggregate source data to subplant levels
    ###########################################################################

    def get_860_by_x(
        self, subplant_id_col="pf_subplant_id", merge_only=False, age_year=2021
    ):
        """
        Map capacity and sum to plant prime fuel subplant level

        """

        coi = (
            pd.read_parquet(PACKAGE_PATH / "unit_level_costs_with_flag.parquet.gzip")
            .pipe(simplify_columns)
            .pipe(month_year_to_date)
            .rename(columns={"plant_id": "plant_id_eia"})
        )[["plant_id_eia", "generator_id", "pollution_control_costs_per_kw"]]

        if age_year is not None:
            reference_date = dt.strptime(f"12-1-{age_year}", "%m-%d-%Y")
        else:
            reference_date = dt.utcnow()

        merged = (
            self.pudl_tabl.gens_eia860()
            .query("operational_status == 'existing'")
            .assign(
                prime_mover=lambda x: x.prime_mover_code.replace(
                    FOSSIL_PRIME_MOVER_MAP
                ),
            )
            .copy()
            .merge(
                coi[["plant_id_eia", "generator_id", "pollution_control_costs_per_kw"]],
                on=["plant_id_eia", "generator_id"],
                how="left",
                validate="m:1",
            )
            .fillna({"pollution_control_costs_per_kw": 0.0})
            .merge(
                self.pudl_tabl.gens_eia860m()
                .query("report_date == report_date.max()")[
                    [
                        "plant_id_eia",
                        "generator_id",
                        "balancing_authority_code_eia",
                        # "state",
                    ]
                ]
                .drop_duplicates(),
                on=["plant_id_eia", "generator_id"],
                how="left",
                # indicator=True,
                validate="m:1",
            )
            .assign(
                age_in_report_year=lambda x: (
                    x["report_date"] - x["generator_operating_date"]
                ).dt.days
                / 365.25,
                age_in_current_year=lambda x: (
                    reference_date - x["generator_operating_date"]
                ).dt.days
                / 365.25,
                age_of_observation=lambda x: (reference_date - x["report_date"]).dt.days
                / 365.25,
                age_relative_to_prime_avg=lambda x: x["age_in_report_year"]
                - x.groupby(["prime_mover"])["age_in_report_year"].transform("mean"),
            )
        )

        if subplant_id_col == "generator_id":
            # have to cast True, False, and NA from tech cols in 860 as 0 and 1
            # since at the PF level, this is done in wt avg

            merged = self.tech_cols_dummy(merged)

            if merge_only:
                logger.warning(
                    "when `subplant_id_col`='generator_id', `merge_only` has no effect"
                )

            return merged[
                # .query('_merge == "both"')
                GET_860_GEN_COLS
            ].pipe(add_ba_code)

        else:
            xwalk = {"pf_subplant_id": self.safe_xwalk, "subplant_id": self.xwalk}[
                subplant_id_col
            ]

            merged = merged.merge(
                xwalk[
                    ["plant_id_eia", "generator_id", subplant_id_col]
                ].drop_duplicates(),
                on=["plant_id_eia", "generator_id"],
                how="outer",
                validate="m:1",
                indicator=True,
            )

            test = (
                merged.query(
                    "_merge != 'both' & prime_mover_code in @FOSSIL_PRIME_MOVER_MAP"
                )
                .replace(
                    {
                        "_merge": {
                            "left_only": "in_data_only",
                            "right_only": "in_xwalk_only",
                        }
                    }
                )
                .groupby(["_merge", "prime_mover_code"], dropna=False)
                .plant_id_eia.nunique()
                .to_frame()
                .query("plant_id_eia > 0")
            )
            logger.warning(
                "860 %s: Unique plants that did not have matches in both "
                "860 and the xwalk so will be dropped:\\n %s \\n",
                {"pf_subplant_id": "prime", "subplant_id": "subplant"}[subplant_id_col],
                test.squeeze().to_dict(),
            )
            if merge_only:
                return merged
            wtavg_dict = {
                "associated_combined_heat_power": "capacity_mw",
                "duct_burners": "capacity_mw",
                "bypass_heat_recovery": "capacity_mw",
                "solid_fuel_gasification": "capacity_mw",
                "carbon_capture": "capacity_mw",
                "fluidized_bed_tech": "capacity_mw",
                "pulverized_coal_tech": "capacity_mw",
                "stoker_tech": "capacity_mw",
                "other_combustion_tech": "capacity_mw",
                "subcritical_tech": "capacity_mw",
                "supercritical_tech": "capacity_mw",
                "ultrasupercritical_tech": "capacity_mw",
                "age_in_report_year": "capacity_mw",
                "age_in_current_year": "capacity_mw",
                "age_of_observation": "capacity_mw",
                "age_relative_to_prime_avg": "capacity_mw",
                "pollution_control_costs_per_kw": "capacity_mw",
            }

            return (
                merged.query("_merge == 'both'")  # overwrite existing age columns
                # AE - I don't think is required, the weighted average should already
                # effectively be what we want here, I'm also removing average ages
                # across subplants because that's what they all are
                # by re-doing with group by at subplant level
                # .assign(
                #     avg_age_from_report_year=lambda x: x.groupby(
                #         ["plant_id_eia", subplant_id_col]
                #     )["age_from_report_year"].transform("mean"),
                #     current_avg_age=lambda x: x.groupby(
                #         ["plant_id_eia", subplant_id_col]
                #     )["current_age"].transform("mean"),
                #     age_relative_to_avg=lambda x: x["current_age"]
                #     - x["avg_age_from_report_year"],
                # )
                .astype({k: float for k in wtavg_dict})
                .fillna({k: 0.0 for k in wtavg_dict})
                .drop(columns=["_merge"])
                .pipe(
                    sum_and_weighted_average_agg,
                    by=[
                        "plant_id_eia",
                        subplant_id_col,
                        pd.Grouper(key="report_date", freq="YS"),
                    ],
                    agg_dict={
                        "capacity_mw": "sum",
                        "prime_mover": "first",
                        "balancing_authority_code_eia": "first",
                        "state": "first",
                        "utility_id_eia": "first",
                        "technology_description": pd.Series.mode,
                    },
                    wtavg_dict=wtavg_dict,
                )
                .astype(
                    {
                        "plant_id_eia": "Int64",
                        subplant_id_col: "Int64",
                        "technology_description": "string",
                    }
                )
                .pipe(add_ba_code)
            )

    def get_gen923_by_subplant(self):
        """
        Args:
        crosswalk (dataframe): grand crosswalk from crosswalk class
        pudl_out : class for extracting pudl data

        Waterfall scenario 1: generation data from GF 923
        Transforms:
        1) create column counting how many gens are in each subplant group
        2) merge gen 923 with crosswalk to get subplant id
        3) filter out generators without a subplant match
        4) create column counting how many gens reported in g 923 are in each
            subplant group
        5) keep rows where gens reported = gens in subplant
        6) throw out CCs reported before 15, we don't trust this G 923 data
        7) aggregate to subplant level annually

        """

        df = (
            self.pudl_tabl.gen_original_eia923()
            .merge(
                self.xwalk.assign(
                    n_gens_subplant=lambda x: x.groupby(
                        ["plant_id_eia", "subplant_id"]
                    )["generator_id"].transform("nunique"),
                    n_primes_subplant=lambda x: x.groupby(
                        ["plant_id_eia", "subplant_id"]
                    )["prime_mover"].transform("nunique"),
                )
                .query("n_primes_subplant == 1")[
                    [
                        "plant_id_eia",
                        "generator_id",
                        "subplant_id",
                        "n_gens_subplant",
                        "prime_mover",
                    ]
                ]
                .drop_duplicates(),
                on=["plant_id_eia", "generator_id"],
                how="left",
                validate="m:1",
            )  # ftiler out generators without a subplant match
            .query("subplant_id.notnull()")
            .assign(
                n_gens_g_923=lambda x: x.groupby(
                    [
                        "plant_id_eia",
                        "subplant_id",
                        pd.Grouper(key="report_date", freq="YS"),
                    ]
                )["generator_id"].transform("nunique")
            )
        )

        # throw out CCs reported before 15, we don't trust this G 923 data
        df = df.loc[~((df["prime_mover"] == "CC") & (df.report_date.dt.year < 2015))]

        logger.warning(
            "Waterfall subset 1: Subplant groups that are not complete (all generators "
            "in that subplant group are reported in G 923) are being dropped "
        )

        return (
            # filter out rows where number of gens in subplant dont match number of gens
            # for that subplant in gen 923
            df.query("n_gens_subplant == n_gens_g_923")
            .groupby(
                [
                    "plant_id_eia",
                    "subplant_id",
                    pd.Grouper(key="report_date", freq="YS"),
                ]
            )
            .net_generation_mwh.sum()
            .reset_index()
        )

    def get_bf923_by_subplant(self, merge_only=False):
        """
        Args:
            by_fuel: pivot by fuel group
            merge_only:

        transform BF 923
        1) make year and unit id pudl as it is in bf table
        2) merge with grand crosswalk on unit id pudl, drop na's they mess up m:1 check
        3) roll up to subplant level

        """
        bf923 = (
            self.pudl_tabl.bf_eia923()
            .pipe(fix_cc_in_prime)
            .pipe(add_fuel_group)
            .merge(
                self.get_elec_pf_gf923(),
                on=["plant_id_eia", "prime_mover", "energy_source_code"],
                how="left",
                validate="m:1",
            )
            .assign(
                # calculate boiler fuel ~mwh using heat rates from gf923
                bf_gross_mwh=lambda x: x.fuel_consumed_mmbtu
                / positive_heat_rate(x, "gf_mmbtu", "gf_mwh"),
                # hr_src=lambda x: positive_heat_rate(
                #     x, "gf_mmbtu", "gf_mwh", src=True
                # ),
                bf_net_mwh=lambda x: x.fuel_consumed_mmbtu * x.gf_mwh / x.gf_mmbtu,
            )
        )

        test = bf923.assign(
            rollup=lambda x: x.groupby(
                ["plant_id_eia", "prime_mover", "energy_source_code", "report_date"]
            ).fuel_consumed_mmbtu.transform("sum")
        )
        z = test[
            ~np.isclose(test.rollup, test.gf_mmbtu, rtol=5e-2)
            & (test.gf_mmbtu > 1000.0)
            & test.gf_mmbtu.notna()
            & ~((test.prime_mover == "CC") & (test.report_date < "2015"))
        ]
        logger.warning(
            "WE HAVE NOT ADDRESSED BF923 WEIRDNESS OF WHICH THERE MIGHT BE %s ROWS",
            len(z),
        )

        # test2 = bf923.set_index(["report_date", "plant_id_eia", "boiler_id"])
        # negatives = test2[
        #     (test2.hr < 0.0)
        #     & (test2.fuel_consumed_mmbtu > 0.0)
        #     & ~(
        #         (test2.prime_mover == "CC")
        #         & (test2.index.get_level_values("report_date") < "2015")
        #     )
        # ].index
        # negatives = test2[
        #     (
        #         test2.groupby(
        #             ["plant_id_eia", "boiler_id", "report_date"]
        #         ).energy_source_code.transform(pd.Series.nunique)
        #         > 1
        #     )
        #     & ~(
        #         (test2.prime_mover == "CC")
        #         & (test2.index.get_level_values("report_date") < "2015")
        #     )
        # ].index
        # (
        #     test2.loc[negatives, :]
        #     .reset_index()
        #     .sort_values(
        #         [
        #             "report_date",
        #             "plant_id_eia",
        #             "boiler_id",
        #             "energy_source_code",
        #         ]
        #     )
        #     .to_clipboard()
        # )

        merged = bf923.pipe(add_fuel_group).merge(
            self.xwalk.query("unit_id_pudl.notnull()")[
                ["plant_id_eia", "unit_id_pudl", "subplant_id"]
            ].drop_duplicates(),
            on=["plant_id_eia", "unit_id_pudl"],
            how="left",
            validate="m:1",
            indicator=True,
        )

        test = (
            merged.query("_merge != 'both' ")
            .groupby(["prime_mover_code"])
            .plant_id_eia.nunique()
            .to_frame()
            .query("plant_id_eia > 0")
        )
        logger.warning(
            "923 boiler fuel: Unique plants that did not have matches in both 923 "
            "boiler fuel and the xwalk so will be dropped:\n %s \n",
            test.squeeze().to_dict(),
        )

        if merge_only:
            return merged
        out = (
            merged.query("_merge == 'both'")
            .rename(columns={"fuel_consumed_mmbtu": "mmbtu"})
            .pivot_table(
                index=[
                    "plant_id_eia",
                    "subplant_id",
                    pd.Grouper(key="report_date", freq="YS"),
                ],
                columns="fuel_group",
                values=["bf_gross_mwh", "bf_net_mwh", "mmbtu"],
                aggfunc={
                    "bf_gross_mwh": "sum",
                    "bf_net_mwh": "sum",
                    "mmbtu": "sum",
                    # "hr_src": sorted_unique_cat,
                },
            )
            .reorder_levels([1, 0], axis=1)
        )
        out.columns = map("_".join, out.columns)
        out = out.loc[:, out.sum(axis=0) != 0].reset_index()
        return out

    def get_gf923_by_subplant(self, scenario_one_subplants):
        """
        Args:
            crosswalk (dataframe): grand crosswalk from crosswalk class
            pudl_out : class for extracting pudl data, stored in crosswalk
                initialization
            scenario_one_subplants: subplants covered by waterfall step/scenario one,
                from :func:`subplants_in_scenario_one`

        Waterfall scenario 2: subplants single and only prime in plant
        1) figure out which subplants are eligible for step 1 (single and only subplant
            with that prime fuel within a plant)
        2) merge gen fuel and filtered grand crosswalk on plant prime
        3) take out subplants covered in scenario 1
        4) change relevant prime mover codes to CC (need to do after previous steps)


        """

        # identify which subplants are the only prime mover within their plant,
        # these are the qualifying subplants
        pf_crosswalk = (
            self.xwalk.assign(
                n_prime_movers_subplant=lambda x: x.groupby(
                    ["plant_id_eia", "subplant_id"]
                )["prime_mover"].transform("nunique"),
            )
            .query("n_prime_movers_subplant == 1")
            .drop_duplicates(subset=["plant_id_eia", "subplant_id"])
            # this step drops subplants that share a prime in a plant, that's what
            # keep=False means
            .drop_duplicates(subset=["plant_id_eia", "prime_mover"], keep=False)
            .assign(
                plant_subplant_id_eia=lambda x: x["plant_id_eia"].astype(str)
                + "_"
                + x["subplant_id"].astype(str)
            )
        )
        pd.testing.assert_frame_equal(
            pf_crosswalk[["plant_id_eia", "subplant_id", "prime_mover"]],
            pf_crosswalk[
                ["plant_id_eia", "subplant_id", "prime_mover"]
            ].drop_duplicates(),
        )

        # grab GF info from list of qualifying subplants
        df = (
            self.pudl_tabl.gf_eia923()
            # moving this up top to allow CC matches
            .pipe(fix_cc_in_prime)
            .pipe(add_fuel_group)
            .assign(
                report_year=lambda x: x.report_date.dt.year,
                bf_gross_mwh=lambda x: x.fuel_consumed_mmbtu
                / positive_heat_rate(x, "fuel_consumed_mmbtu", "net_generation_mwh"),
                # hr_src=lambda x: positive_heat_rate(
                #     x, "fuel_consumed_mmbtu", "net_generation_mwh", src=True
                # ),
            )
            .merge(
                pf_crosswalk[["plant_id_eia", "subplant_id", "prime_mover"]],
                on=["plant_id_eia", "prime_mover"],
                how="left",
                validate="m:1",
                indicator=True,
            )
            .dropna(subset="report_year")
        )
        msg = (
            df.query("_merge != 'both' & prime_mover in @FOSSIL_PRIME_MOVER_MAP")
            .groupby(["prime_mover"], dropna=False)
            .plant_id_eia.nunique()
            .to_frame()
            .query("plant_id_eia > 0")
        )

        logger.warning(
            "Waterfall subset 2 gf923: Subplant groups that are not the single and "
            "only prime mover within their plant are being dropped %s",
            msg.to_dict(),
        )

        out = (
            df.rename(
                columns={
                    "net_generation_mwh": "net_mwh",
                    "fuel_consumed_mmbtu": "mmbtu",
                }
            )
            .pivot_table(
                index=[
                    "plant_id_eia",
                    "subplant_id",
                    pd.Grouper(key="report_date", freq="YS"),
                ],
                columns="fuel_group",
                values=["net_mwh", "bf_gross_mwh", "mmbtu"],
                aggfunc={
                    "bf_gross_mwh": "sum",
                    "net_mwh": "sum",
                    "mmbtu": "sum",
                    # "hr_src": sorted_unique_cat,
                },
            )
            .reorder_levels([1, 0], axis=1)
        )
        out.columns = map("_".join, out.columns)
        return (
            out.reset_index()
            .assign(
                year=lambda x: x["report_date"].dt.year,
                plant_subplant_year_eia=lambda x: x[
                    ["plant_id_eia", "subplant_id", "year"]
                ]
                .astype(str)
                .agg("_".join, axis=1),
                net_generation_mwh=lambda x: x.filter(like="_net_mwh").sum(axis=1),
            )
            .query("plant_subplant_year_eia not in @scenario_one_subplants")
            .drop(columns=["plant_subplant_year_eia", "year"])
        )

    def get_gf923_by_prime(self, merge_only=False):
        """
        transform GF 923
        1) CT, CS, and CA's to CC
        2) make prime mover and plant prime fuel column for later mergers
        3) sum annual net gen and fuel consumption for plant prime fuel
        4) create dictionary with plant prime fuel totals
        4) map those totals to grand crosswalk


        """
        # drop nuclear, solar, geothermal, and waste heat
        # energy source codes that we grab from step 3

        merged = (
            self.pudl_tabl.gf_eia923()
            # AE - Uday categorizes wast heat as other so I made that change
            # in constants
            .query("energy_source_code not in ('GEO', 'NUC', 'SUN')")
            .pipe(fix_cc_in_prime)
            .pipe(add_fuel_group)
            .assign(
                bf_gross_mwh=lambda x: x.fuel_consumed_mmbtu
                / positive_heat_rate(x, "fuel_consumed_mmbtu", "net_generation_mwh"),
                # hr_src=lambda x: positive_heat_rate(
                #     x, "fuel_consumed_mmbtu", "net_generation_mwh", src=True
                # ),
            )
            .rename(
                columns={
                    "net_generation_mwh": "net_mwh",
                    "fuel_consumed_mmbtu": "mmbtu",
                }
            )
            .pivot_table(
                index=["plant_id_eia", "prime_mover", "report_date"],
                columns="fuel_group",
                values=["net_mwh", "bf_gross_mwh", "mmbtu"],
                aggfunc={
                    "bf_gross_mwh": "sum",
                    "net_mwh": "sum",
                    "mmbtu": "sum",
                    # "hr_src": sorted_unique_cat,
                },
            )
            .reorder_levels([1, 0], axis=1)
        )
        merged.columns = map("_".join, merged.columns)
        merged = merged.reset_index().merge(
            self.xwalk[
                ["plant_id_eia", "pf_subplant_id", "prime_mover"]
            ].drop_duplicates(),
            on=["plant_id_eia", "prime_mover"],
            how="left",
            validate="m:1",
            indicator=True,
        )
        test = (
            merged.query("_merge != 'both' & prime_mover in @FOSSIL_PRIME_MOVER_MAP")
            .groupby(["prime_mover"])
            .plant_id_eia.nunique()
            .to_frame()
            .query("plant_id_eia > 0")
        )
        logger.warning(
            "923: Unique plants that did not have matches in both 923 and the xwalk so "
            "will be dropped:\n %s \n",
            test.squeeze().to_dict(),
        )
        if merge_only:
            return merged
        return (
            merged.query("_merge == 'both'")
            .astype({"plant_id_eia": int, "pf_subplant_id": int})
            .drop(columns=["_merge"])
            .groupby(
                [
                    "plant_id_eia",
                    "pf_subplant_id",
                    pd.Grouper(key="report_date", freq="YS"),
                ]
            )
            .sum()
            .reset_index()
            .assign(net_generation_mwh=lambda x: x.filter(like="_net_mwh").sum(axis=1))
        )

    def get_gf923_by_generator(self, counterfactuals=False):
        gf_923 = (
            self.pudl_tabl.gen_fuel_by_generator_energy_source_eia923()
            .pipe(add_fuel_group)
            .rename(
                columns={
                    "net_generation_mwh": "net_mwh",
                    "fuel_consumed_mmbtu": "mmbtu",
                }
            )
        )

        if counterfactuals is False:
            gf_923 = gf_923.pivot_table(
                index=[
                    "plant_id_eia",
                    "generator_id",
                    pd.Grouper(key="report_date", freq="YS"),
                ],
                columns="fuel_group",
                values=["net_mwh", "mmbtu"],
                aggfunc={
                    "net_mwh": "sum",
                    "mmbtu": "sum",
                    # "hr_src": sorted_unique_cat,
                },
            ).reorder_levels([1, 0], axis=1)

            gf_923.columns = map("_".join, gf_923.columns)

            return gf_923.reset_index().assign(
                net_generation_mwh=lambda x: x.filter(like="_mwh").sum(axis=1)
            )

        return gf_923

    def get_cems_by_x(self, subplant_id_col, xwalk=None, merge_only=False):
        """
        Adding CEMS data to waterfall
        Three main steps:
        1) create plant/ unit totals with camd data
        2) dictionary with plant/unit as key: gross gen, gross gen max, gen/fuel
            starts as value
        3) map onto grand crosswalk, aggregate camd info to plant prime fuel
            subplant level

        """
        if xwalk is None:
            xwalk = self.xwalk

        merged = self.get_cems().merge(
            xwalk[
                [
                    "plant_id_epa",
                    "plant_id_eia",
                    "emissions_unit_id_epa",
                    subplant_id_col,
                ]
            ]
            .dropna(axis=0, subset=["plant_id_epa", "emissions_unit_id_epa"])
            .drop_duplicates(),
            on=["plant_id_epa", "emissions_unit_id_epa"],
            how="outer",
            validate="m:1",
            indicator=True,
        )
        test = (
            merged.fillna({"plant_id_epa": merged.plant_id_eia})
            .query("_merge != 'both'")
            .replace({"_merge": {"left_only": "data_only", "right_only": "xwalk_only"}})
            .assign(year=lambda x: x.report_date.dt.year)
            .groupby(["_merge", "year"], dropna=False)
            .plant_id_epa.nunique()
            .to_frame()
            .query("plant_id_epa > 0")
        )
        logger.warning(
            "CEMS %s: Unique plants that did not have matches in both "
            "CEMS and the xwalk so will be dropped:\n %s \n",
            {"pf_subplant_id": "prime", "subplant_id": "subplant"}[subplant_id_col],
            test.squeeze().to_dict(),
        )
        if merge_only:
            return merged
        aggs = {
            "generator_starts": "sum",
            "fuel_starts": "sum",
            "gross_generation_mwh": "sum",
            "heat_in_mmbtu": "sum",
            "co2_tons": "sum",
        }
        return (
            merged.query("_merge == 'both'")
            .drop(columns=["_merge"])
            .groupby(["plant_id_eia", subplant_id_col, "report_date"])
            .agg(aggs | {"camd_capacity_mw": "sum"})
            .reset_index()
            .groupby(
                [
                    "plant_id_eia",
                    subplant_id_col,
                    pd.Grouper(key="report_date", freq="YS"),
                ],
                dropna=False,
            )
            .agg(aggs | {"camd_capacity_mw": "max"})
            .reset_index()
            .astype({"plant_id_eia": "Int64", subplant_id_col: "Int64"})
        )

    def get_cems_by_generator(self, xwalk=None):
        if xwalk is None:
            xwalk = self.xwalk

        merged = (
            self.get_cems()[
                [
                    "plant_id_epa",
                    "emissions_unit_id_epa",
                    "report_date",
                    "generator_starts",
                    "fuel_starts",
                    "gross_generation_mwh",
                    "camd_capacity_mw",
                ]
            ]
            .merge(
                xwalk[
                    [
                        "plant_id_epa",
                        "plant_id_eia",
                        "emissions_unit_id_epa",
                        "generator_id",
                        "capacity_xwalk",
                        "subplant_id",
                    ]
                ]
                .dropna(axis=0, subset=["plant_id_epa", "emissions_unit_id_epa"])
                .drop_duplicates(),
                on=["plant_id_epa", "emissions_unit_id_epa"],
                how="outer",
                validate="m:m",
                indicator=True,
            )
            .query('_merge == "both"')
            .groupby(
                [
                    "plant_id_eia",
                    "subplant_id",
                    pd.Grouper(key="report_date", freq="YS"),
                ]
            )
            .agg(
                {
                    "gross_generation_mwh": "sum",
                    "generator_starts": "sum",
                    "fuel_starts": "sum",
                }
            )
            .reset_index()
        )

        merged_with_gf_frac = (
            self.pudl_tabl.gen_fuel_allocated_eia923()
            .groupby(
                [
                    "plant_id_eia",
                    "generator_id",
                    pd.Grouper(key="report_date", freq="YS"),
                ]
            )
            .agg({"fuel_consumed_mmbtu": "sum"})
            .reset_index()
            .merge(
                xwalk[
                    ["plant_id_eia", "generator_id", "subplant_id"]
                ].drop_duplicates(),
                on=["plant_id_eia", "generator_id"],
                how="outer",
                validate="m:1",
                indicator=True,
            )
            .assign(
                subplant_fuel_consumed_mmbtu=lambda x: x.groupby(
                    ["plant_id_eia", "subplant_id", "report_date"]
                )["fuel_consumed_mmbtu"].transform("sum"),
                gen_fuel_consumed_frac=lambda x: x.fuel_consumed_mmbtu
                / x.subplant_fuel_consumed_mmbtu,
            )
            .merge(
                merged,
                on=["plant_id_eia", "subplant_id", "report_date"],
                how="outer",
                validate="m:1",
                indicator="exists",
            )
            .assign(
                gross_generation_mwh=lambda x: x.gross_generation_mwh
                * x.gen_fuel_consumed_frac
            )
            .assign(
                gross_generation_mwh=lambda x: x["gross_generation_mwh"].fillna(0.0)
            )
        )

        return merged_with_gf_frac.query('_merge == "both" & exists == "both"')[
            [
                "plant_id_eia",
                "generator_id",
                "report_date",
                "generator_starts",
                "fuel_starts",
                "gross_generation_mwh",
            ]
        ]

    def add_costs(self, df: pd.DataFrame, on="subplant_id"):
        id_cols = ["plant_id_eia", "prime_mover", "report_date"]
        d_cols = [
            "subplant_id",
            "pf_subplant_id",
            "inflator_to_2021",
            "wage_scale",
            "age_of_observation_secular_adj",
            "real_capex_per_kw",
            "real_opex_per_kw",
            "opex_per_kw",
            "capex_per_kw",
            "arc_per_kw",
        ]
        if "costs" not in self._dfs:
            dtypes = {"plant_id_eia": "Int64", "prime_mover": "string"}
            cost = (
                pd.read_parquet(
                    PACKAGE_PATH / "860_FERC_matching_cost_regressions.parquet.gzip",
                )
                .pipe(simplify_columns)
                .rename(columns={"plant": "plant_id_eia", "prime": "prime_mover"})
                .astype(dtypes)
                .assign(report_month=1)
                .pipe(month_year_to_date)
                .assign(counts=lambda x: x.groupby(id_cols).fuel_1.transform("count"))
                .merge(
                    self.get_wage_scale(),
                    on=["report_date", "state"],
                    how="left",
                    validate="m:1",
                )
                .fillna({"wage_scale": 1})
                .merge(
                    self.xwalk.drop_duplicates(
                        subset=[
                            "plant_id_eia",
                            "prime_mover",
                            "subplant_id",
                            "pf_subplant_id",
                        ]
                    ),
                    on=["plant_id_eia", "prime_mover"],
                    how="left",
                    validate="m:m",
                )
                .sort_values(
                    [
                        "plant_id_eia",
                        "subplant_id",
                        "pf_subplant_id",
                        "prime_mover",
                        "report_date",
                    ]
                )
                .assign(
                    sbi_count=lambda x: x.groupby(
                        ["plant_id_eia", "subplant_id", "report_date"]
                    ).wage_scale.transform(pd.Series.nunique),
                    psbi_count=lambda x: x.groupby(
                        ["plant_id_eia", "pf_subplant_id", "report_date"]
                    ).wage_scale.transform(pd.Series.nunique),
                )
            )
            cost = cost[cost.counts == 1]
            assert (  # noqa: S101
                cost.query(  # noqa: S101
                    "sbi_count > 1"
                ).empty
            ), "adding subplants to costs created non-unique costs per subplant_id"
            assert cost.query("psbi_count > 1").empty, (  # noqa: S101
                "adding pf_subplants to costs created "
                "non-unique costs per pf_subplant_id"
            )
            self._dfs["costs"] = cost[id_cols + d_cols]

        dt = df.dtypes.astype("string").to_dict()

        return (
            df.astype(
                {"plant_id_eia": int}
                | {
                    x: int
                    for x in ("subplant_id", "pf_subplant_id")
                    if all((x in df, x == on))
                }
            )
            .merge(
                self._dfs["costs"].drop_duplicates(
                    subset=["plant_id_eia", on, "report_date"]
                ),
                on=["plant_id_eia", on, "report_date"],
                validate="m:1",
                how="left",
                indicator="ferc_merge",
                suffixes=("", "_dup"),
            )
            .assign(
                real_capex=lambda x: x.real_capex_per_kw * x.capacity_mw * 1e3,
                real_opex=lambda x: x.real_opex_per_kw * x.capacity_mw * 1e3,
                capex=lambda x: x.capex_per_kw * x.capacity_mw * 1e3,
                opex=lambda x: x.opex_per_kw * x.capacity_mw * 1e3,
                arc=lambda x: x.arc_per_kw * x.capacity_mw * 1e3,
            )
            .astype(dt)
        )

    def get_wage_scale(self):
        fip = pd.read_csv(PACKAGE_PATH / "State_FIPS_Match.csv")
        return (
            pd.read_parquet(PACKAGE_PATH / "wage_data.parquet.gzip")
            .assign(total_wages=lambda x: x.avg_annual_pay * x.annual_avg_emplvl)
            .groupby(["area_fips", "year"])[["annual_avg_emplvl", "total_wages"]]
            .sum()
            .sort_index()
            .reset_index()
            .assign(
                wages=lambda x: (x.total_wages / x.annual_avg_emplvl).mask(
                    x.annual_avg_emplvl <= 0, pd.NA
                ),
                wage_scale=lambda x: (
                    x.wages / x.groupby("year").wages.transform("mean")
                ).fillna(1.0),
                state=lambda x: x.area_fips.map(
                    fip.set_index("area_fips")["State"].to_dict()
                ),
                report_month=1,
                age_of_observation_secular_adj=lambda x: x.groupby(
                    ["state"]
                ).wage_scale.transform("cumsum"),
            )
            .rename(columns={"year": "report_year"})
            .dropna(subset="state")
            .pipe(month_year_to_date)[
                ["report_date", "state", "wage_scale", "age_of_observation_secular_adj"]
            ]
        )

    def get_elec_pf_gf923(self):
        rname = {
            "fuel_consumed_mmbtu": "gf_mmbtu",
            "fuel_consumed_for_electricity_mmbtu": "gf_elec_mmbtu",
            "net_generation_mwh": "gf_mwh",
        }
        prime_fuel_heat_rates = (
            self.pudl_tabl.gf_eia923()
            .pipe(fix_cc_in_prime)
            .rename(columns=rname)
            .groupby(["plant_id_eia", "prime_mover", "energy_source_code"])[
                list(rname.values())
            ]
            .sum()
            .reset_index()
        )

        return prime_fuel_heat_rates

    def tech_cols_dummy(self, df):
        techs = [
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
        ]

        for tech in techs:
            df[tech] = np.where(df[tech].isna() | df[tech] is False, 0, 1)

        return df

    @staticmethod
    def core_validation(df, level):
        """

        Args:
            merge_all_df (Dataframe): unvalidated output
        Returns:

            merge_all_df (Dataframe): Validated output


        """
        fuels = (
            "biofuel",
            "coal",
            "natural_gas",
            "other",
            "other_gas",
            "petroleum",
            "petroleum_coke",
        )
        techs = (
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
        )

        core_columns = (
            {
                "plant_id_eia": Column(int),
                "report_date": Column(dt),
                "prime_mover": Column(str, Check.isin(tuple(FOSSIL_PRIME_MOVER_MAP))),
                "report_year": Column(int, nullable=True),
                "capacity_mw": Column(float, Check.in_range(1e-1, 1e4)),
                "gross_cf": Column(float, nullable=True),
                "generator_starts": Column(int, Check.ge(0)),
                "pollution_control_costs_per_kw": Column(float, Check.ge(0.0)),
                "real_pollution_control_costs_per_kw": Column(float, Check.ge(0.0)),
                "wage_scale": Column(float),
                "respondent_id": Column(pd.Int64Dtype(), nullable=True),
                "respondent_id_purchaser": Column(pd.Int64Dtype(), nullable=True),
                "final_respondent_id": Column(pd.Int64Dtype(), nullable=True),
                "final_ba_code": Column(str, nullable=True),
                "state": Column(str),
                "utility_id_eia": Column(pd.Int64Dtype(), nullable=True),
                "balancing_authority_code_eia": Column(str, nullable=True),
            }
            | {
                "age_of_observation_secular_adj": Column(float),
                "age_of_observation": Column(float, Check.in_range(0.0, 2e3)),
                "age_relative_to_prime_avg": Column(float),
            }
            | {f"{k}_fraction": Column(float, Check.in_range(0.0, 1.0)) for k in fuels}
            | {"minor_fuels_fraction": Column(float, Check.in_range(0.0, 1.0))}
            | {k: Column(float, Check.in_range(0.0, 1.0)) for k in techs}
            # not used in regression
            | {
                "age_in_report_year": Column(float),
                "age_in_current_year": Column(float, Check.in_range(0.0, 2e3)),
                "gross_generation_mwh": Column(float),
                "net_generation_mwh": Column(float),
                "inflator_to_2021": Column(float),
                "fuel_starts": Column(int, Check.ge(0)),
            }
            | {f"{k}_mmbtu": Column(float, Check.ge(0.0), nullable=True) for k in fuels}
            | {f"{k}_net_mwh": Column(float, nullable=True) for k in fuels}
            | {
                f"{k}_gross_mwh": Column(float, Check.ge(0.0), nullable=True)
                for k in fuels
            }
        )

        merge_all_columns = (
            {
                "pf_subplant_id": Column(int),
                "subplant_id": Column("Int64", nullable=True),
                "step": Column(int, Check.isin((1, 2, 3))),
                "cum_starts": Column(int, Check.ge(0)),
            }
            | {
                "parasitic_load_pct": Column(float),
                "camd_capacity_mw": Column(float, Check.in_range(0.0, 1e4)),
                "gross_hr": Column(float, Check.ge(0.0), nullable=True),
                "heat_in_mmbtu": Column(float, Check.ge(0.0)),
                "net_cf": Column(float, nullable=True),
                "arc": Column(float, nullable=True),
                "opex": Column(float, Check.ge(0.0), nullable=True),
                "real_capex": Column(float, Check.ge(0.0), nullable=True),
                "opex_per_kw": Column(float, Check.ge(0.0), nullable=True),
                "capex_per_kw": Column(float, Check.ge(0.0), nullable=True),
            }
            | {f"{k}_gross_cf": Column(float) for k in fuels}
        )

        gen_columns = {
            "generator_id": Column(str),
            "generator_operating_date": Column(dt),
            "technology_description": Column(str, nullable=True),
            "gross_gen_value": Column(str),
        }

        def gross_ge_net(df_):
            return df_.gross_generation_mwh >= df_.net_generation_mwh

        def x_gen_allocation(df_, kind):
            return pd.Series(
                np.isclose(
                    df_.filter(like=f"_{kind}_mwh").sum(axis=1),
                    df_[f"{kind}_generation_mwh"],
                    rtol=2e-2,
                ),
                index=df_.index,
            )

        def valid_generation(df_):
            hrs = np.where(df_.report_date.dt.is_leap_year, 8784, 8760)
            return df_.net_generation_mwh <= df_.capacity_mw * hrs * 1.3

        if level == "generator":
            schema = pa.DataFrameSchema(
                columns=core_columns | gen_columns,
                checks=[
                    Check(
                        gross_ge_net,
                        title="net_gen >= gross_gen",
                        description="Gross generation should always be greater than net",
                        # I don't think we want to error here yet, so just raise a warning  # noqa: W505
                        raise_warning=True,
                    ),
                    Check(
                        x_gen_allocation,
                        title="net_gen aggregation",
                        kind="net",
                        raise_warning=True,
                    ),
                    # Check(
                    # x_gen_allocation, title="gross_gen aggregation", kind="gross"
                    # ),
                    # I don't think we want to error here yet, so just raise a warning
                    Check(valid_generation, title="valid net gen", raise_warning=True),
                ],
                unique=["plant_id_eia", "generator_id", "report_date"],
                index=pa.Index(int),
                strict=False,
                coerce=True,
                ordered=False,
            )
            df = schema.validate(df[core_columns | gen_columns])

            return df

        else:
            schema = pa.DataFrameSchema(
                # columns=core_columns,
                columns=core_columns | merge_all_columns,
                checks=[
                    Check(
                        gross_ge_net,
                        title="net_gen >= gross_gen",
                        description="Gross generation should always be greater than net",
                        # I don't think we want to error here yet, so just raise a warning  # noqa: W505
                        raise_warning=True,
                    ),
                    Check(x_gen_allocation, title="net_gen aggregation", kind="net"),
                    Check(
                        x_gen_allocation, title="gross_gen aggregation", kind="gross"
                    ),
                    # I don't think we want to error here yet, so just raise a warning
                    Check(valid_generation, title="valid net gen", raise_warning=True),
                ],
                unique=["plant_id_eia", "subplant_id", "pf_subplant_id", "report_date"],
                index=pa.Index(int),
                strict=False,
                coerce=True,
                ordered=False,
            )

            # df = schema.validate(df[core_columns])
            df = schema.validate(df[core_columns | merge_all_columns])

            return df

    def filter_to_single_fuel_generators(self, df):
        """
        Args:

        df (DataFrame): data frame with historical information on generators
        filtered_df (Dataframe): data frame with only single-fuel generators
        by our definition (>= 90 percent of fuel consumption reported in
        GF 923, pudl allocated)


        """
        # list of cols we need for melt
        fuel_consump_cols = [
            "biofuel_mmbtu",
            "coal_mmbtu",
            "natural_gas_mmbtu",
            # "nuclear_mmbtu",
            "other_mmbtu",
            "other_gas_mmbtu",
            "petroleum_mmbtu",
            "petroleum_coke_mmbtu",
            # "renew_mmbtu",
        ]

        filtered_df = (
            df.melt(
                id_vars=["plant_id_eia", "generator_id", "report_date"],
                value_vars=fuel_consump_cols,
                var_name="mmbtu",
                value_name="fuel_consumption",
            )
            .assign(
                # net_generation=lambda x: x["mmbtu"].abs(),
                percent_of_gen=lambda x: (
                    x["fuel_consumption"]
                    / x.groupby(["plant_id_eia", "generator_id", "report_date"])[
                        "fuel_consumption"
                    ].transform("sum")
                ),
                single_fuel=lambda x: np.where(x["percent_of_gen"] >= 0.9, 1, 0),
                single_fuel_present=lambda x: x.groupby(
                    ["plant_id_eia", "generator_id", "report_date"]
                )["single_fuel"].transform("sum"),
            )
            .query("single_fuel_present == 1 & percent_of_gen >= .9")
        )

        return filtered_df

    def find_missing_data(self):
        """
        objective:
        identify generators with missing data, that we need to fill in historical data
        for

        process:
        1) instances when a generator doesn't report for entire patio range
        2) instances when a single fuel generator switches fuel
        3) zeroes reported (tbd)

        output: df with plant / gen / year / prime / fuel / ba code / age / fuss
        that we want to fill in with similar plants

        """
        hist_data = self.get_historical_by_generator()

        xwalk = self.xwalk

        df_860 = self.get_860_by_x(subplant_id_col="generator_id")

        df_923_cf = self.get_gf923_by_generator(counterfactuals=True)

        # list of cols we need for melt

        """
        missing data type #1: find generators that don't repeat for complete year range
        and spit out plant / gen / missing year / prime / fuel

        prime and fuel based on latest reported (and highest mmbtu) PF
        observation in allocated GF923

        """
        _h = hist_data[["plant_id_eia", "generator_id"]].drop_duplicates()

        missing_years = (
            pd.concat(
                _h.assign(report_date=rd) for rd in hist_data.report_date.unique()
            )
            .merge(
                hist_data[["plant_id_eia", "generator_id", "report_date"]],
                on=["plant_id_eia", "generator_id", "report_date"],
                how="outer",
                indicator="exists",
            )
            .query('exists == "left_only"')
            .assign(fuss=lambda x: "missing_years")
            .merge(
                df_923_cf.groupby(
                    [
                        "plant_id_eia",
                        "generator_id",
                        pd.Grouper(key="report_date", freq="YS"),
                        "prime_mover_code",
                        "fuel_group",
                    ]
                )
                .agg({"mmbtu": "sum", "net_mwh": "sum"})
                .reset_index()  # keep latest prime fuel observation in gf 923 (largest single fuel)
                # .query('report_date == "2020-01-01"')
                # .query("mmbtu > 0 & net_mwh > 0") do we want to put prime/fuel of gens in GF  # noqa: W505
                # reporting zeros?
                .sort_values(
                    by=["plant_id_eia", "generator_id", "report_date", "mmbtu"],
                    ascending=True,
                )
                .drop_duplicates(subset=["plant_id_eia", "generator_id"], keep="last")[
                    [
                        "plant_id_eia",
                        "generator_id",
                        # "report_date",
                        "prime_mover_code",
                        "fuel_group",
                    ]
                ],
                on=["plant_id_eia", "generator_id"],
                how="left",
            )
            .assign(
                prime_mover=lambda x: x.prime_mover_code.replace(
                    FOSSIL_PRIME_MOVER_MAP
                ),
                # age_in_current_year=lambda x: 1,
            )
            .merge(
                df_860.sort_values(
                    by=["plant_id_eia", "generator_id", "report_date"], ascending=True
                ).drop_duplicates(subset=["plant_id_eia", "generator_id"])[
                    [
                        "plant_id_eia",
                        "generator_id",
                        # "report_date",
                        "utility_id_eia",
                        "respondent_id",
                        "respondent_id_purchaser",
                        "state",
                        "final_ba_code",
                        "generator_operating_date",
                        "final_respondent_id",
                        "balancing_authority_code_eia",
                        # "age_in_current_year", not sure what we wanna do about age in this scenario  # noqa: W505
                    ]
                ],
                on=["plant_id_eia", "generator_id"],
                how="left",
                validate="m:1",
                # indicator=True,
            )
            .drop_duplicates(
                subset=[
                    "plant_id_eia",
                    "generator_id",
                    "report_date",
                    "prime_mover",
                    "fuel_group",
                ]
            )
        )[
            [
                "plant_id_eia",
                "generator_id",
                "utility_id_eia",
                "respondent_id",
                "respondent_id_purchaser",
                "state",
                "report_date",
                "fuss",
                "prime_mover",
                "fuel_group",
                "final_ba_code",
                # "age_in_current_year",
                "generator_operating_date",
                "final_respondent_id",
                "balancing_authority_code_eia",
            ]
        ]

        """
        create data frame of generators that switch fuels

        """

        single_fuel_switch = (
            hist_data.pipe(self.filter_to_single_fuel_generators)
            .assign(
                n_fuels=lambda x: x.groupby(["plant_id_eia", "generator_id"])[
                    "mmbtu"
                ].transform("nunique")
            )
            .query("n_fuels > 1")
            .assign(
                fuss=lambda x: "fuel_switch",
                # year=lambda x: x["report_date"].dt.year,
                fuel=lambda x: x.groupby(["plant_id_eia", "generator_id"])[
                    "mmbtu"
                ].transform("last"),
            )
            .query("mmbtu != fuel")
            .assign(fuel_group=lambda x: x["fuel"].str.replace("_mmbtu", ""))
            .merge(
                xwalk[["plant_id_eia", "generator_id", "prime_mover", "fuel_group"]],
                on=["plant_id_eia", "generator_id", "fuel_group"],
                how="left",
            )
            .drop_duplicates(
                subset=["plant_id_eia", "generator_id", "prime_mover", "fuel_group"]
            )
        )
        """
        Missing data type #3: identify plant, gen, prime, fuel observations
        reporting zero net gen and fuel consumption

        """
        zero_reported = (
            df_923_cf.assign(
                n_fuels=lambda x: x.groupby(
                    ["plant_id_eia", "generator_id", "report_date"]
                )["energy_source_code_num"].transform("nunique")
            )
            .query("n_fuels == 1")
            .drop(columns=["n_fuels"])
            .groupby(
                [
                    "plant_id_eia",
                    "generator_id",
                    pd.Grouper(key="report_date", freq="YS"),
                    "prime_mover_code",
                    "fuel_group",
                ]
            )
            .agg({"net_mwh": "sum", "mmbtu": "sum"})
            .reset_index()
            .query(
                'net_mwh == 0 & mmbtu == 0 & report_date >= "2006-01-01" & report_date <= "2020-01-01"'
            )
            .assign(
                prime_mover=lambda x: x.prime_mover_code.replace(
                    FOSSIL_PRIME_MOVER_MAP
                ),
                # year=lambda x: x["report_date"].dt.year,
                fuss="zeroes",
            )
            # .drop(columns=["percent_of_gen", "single_fuel", "single_fuel_present"])
        )
        zero_and_fuel_switch = pd.concat([single_fuel_switch, zero_reported]).merge(
            df_860[
                [
                    "plant_id_eia",
                    "generator_id",
                    "report_date",
                    "utility_id_eia",
                    "respondent_id",
                    "respondent_id_purchaser",
                    "state",
                    "final_ba_code",
                    "generator_operating_date",
                    "final_respondent_id",
                    "balancing_authority_code_eia",
                    # "age_in_current_year", not sure what we w
                ]
            ],
            on=["plant_id_eia", "generator_id", "report_date"],
            how="left",
            # indicator=True,
        )

        return (
            pd.concat([missing_years, zero_and_fuel_switch])
            # drop duplicates and keep first since we don't want zeroes
            .drop_duplicates(
                subset=[
                    "plant_id_eia",
                    "generator_id",
                    "report_date",
                    # "prime_mover",
                    # "fuel_group",
                ],
                keep="first",
            )
            .assign(
                age=lambda x: (
                    ((pd.datetime.now() - x.generator_operating_date).dt.days) / 365.25
                ).round(2)
            )
        )

    def create_fill_in_ep_thresholds(self, df):
        bins = [0, 10, 20, 30, 40, 50, 60, 70, 100]

        labels = [1, 2, 3, 4, 5, 6, 7, 8]

        return df.assign(
            essentials=lambda x: x["report_date"].astype(str)
            + "_"
            + x["prime_mover"]
            + "_"
            + x["fuel_group"],
            ba_plus_essentials=lambda x: x["essentials"] + "_" + x["final_ba_code"],
            age_range=lambda x: pd.cut(x["age"], bins=bins, labels=labels),
            ba_plus_age=lambda x: x["ba_plus_essentials"]
            + "_"
            + x["age_range"].astype(str),
        )

    def fill_in_ep_data(self, age_year=2021):
        if age_year is not None:
            reference_date = dt.strptime(f"12-1-{age_year}", "%m-%d-%Y")
        else:
            reference_date = dt.utcnow()

        # instances we need
        xwalk = self.xwalk
        # df_860 = self.get_860_by_x(subplant_id_col="generator_id")

        historical = (
            self.get_historical_by_generator()
            .merge(
                xwalk[["plant_id_eia", "generator_id", "prime_mover", "fuel_group"]],
                on=["plant_id_eia", "generator_id", "prime_mover"],
                how="left",
            )
            .assign(
                age=lambda x: (
                    ((pd.datetime.now() - x.generator_operating_date).dt.days) / 365.25
                ).round(2),
                report_year=lambda x: x.report_date.dt.year,
            )
            # .assign(year=lambda x: x["report_date"].dt.year)
            .pipe(self.create_fill_in_ep_thresholds)
        )

        missing = (
            self.find_missing_data()
            .pipe(self.create_fill_in_ep_thresholds)
            .assign(
                essentials_present=lambda x: np.where(
                    x["essentials"].isin(historical["essentials"]),
                    "essentials",
                    pd.NA,
                ),
                ba_plus_essentials_present=lambda x: np.where(
                    x["ba_plus_essentials"].isin(historical["ba_plus_essentials"]),
                    "ba_plus_essentials",
                    pd.NA,
                ),
                ba_plus_age_present=lambda x: np.where(
                    x["ba_plus_age"].isin(historical["ba_plus_age"]),
                    "ba_plus_age",
                    pd.NA,
                ),
            )  # make an exception of when there is no ba code or age
            .assign(
                ba_plus_age_present=lambda x: np.where(
                    (x["final_ba_code"].isnull()) | (x["age"].isnull()),
                    pd.NA,
                    x["ba_plus_age_present"],
                ),
                ba_plus_essentials_present=lambda x: np.where(
                    (x["final_ba_code"].isnull()),
                    pd.NA,
                    x["ba_plus_essentials_present"],
                ),
                # fill_in_score=lambda x: np.where(
                # x["ba_plus_age_present"].notnull(), x["ba_plus_age_present"]
                # ),
                match=lambda x: x["ba_plus_age_present"]
                .fillna(x["ba_plus_essentials_present"])
                .fillna(x["essentials_present"]),
            )
        )

        """
        Fill in part #1: generation and fuel consumption
        Merge missing data df with historical data
        1) Loop based on unique values in match column
        2) Query based on value (list with different kind of matches)
        3) Merge
        4) Append to a list
        5) drop duplicates since they're might be multiple matches

        """

        cols = ["ba_plus_age", "ba_plus_essentials", "essentials"]
        filled_in = []

        for col in cols:
            # core columns we want to get from historical, append column we're going to merge on  # noqa: W505

            # keep plant specific id columns - plant/gen/utility/ba ids (don't want to fill that in with historical)  # noqa: W505
            df = (
                missing[FILL_IN_EP_COLS]
                .query("match == @col")
                .merge(historical[HIST_EP_COLS + [col]], on=[col], how="inner")
                .drop_duplicates(subset=["plant_id_eia", "generator_id", "report_date"])
            )

            filled_in.append(df)

        # remove columns not in historical df for future concat, excpt mtch and fuss
        filled_in_hist_cols = (
            pd.concat(filled_in)
            .drop(
                columns=[
                    "ba_plus_age",
                    "ba_plus_essentials",
                    "essentials",
                    "fuel_group",
                ]
            )
            .sort_values(
                by=["plant_id_eia", "generator_id", "report_date"], ascending=True
            )
            .query("prime_mover in @FOSSIL_PRIME_MOVER_MAP")
            .assign(report_year=lambda x: x.report_date.dt.year)
        )

        """
        Now that we have missing data w/
        historical generation + fuel consumption
        Move on to:
        Fill in part #2: capacity + tech cols
        Merge filled in data with latest (2020?) 860 info
        Fill in part #3: (w)age cols to recalculate
        """

        current = (
            filled_in_hist_cols.merge(
                historical[CURRENT_EP_COLS]
                .drop_duplicates(subset=["plant_id_eia", "generator_id"], keep="last")
                .drop(columns=["report_date"]),
                on=["plant_id_eia", "generator_id"],
                how="inner",  # inner merge to only keep generators in get_exa subset
                validate="m:1",
            )
            .assign(  # re-do age calculations
                age_in_report_year=lambda x: (
                    x["report_date"] - x["generator_operating_date"]
                ).dt.days
                / 365.25,
                age_in_current_year=lambda x: (
                    reference_date - x["generator_operating_date"]
                ).dt.days
                / 365.25,
                age_of_observation=lambda x: (reference_date - x["report_date"]).dt.days
                / 365.25,
                age_relative_to_prime_avg=lambda x: x["age_in_report_year"]
                - x.groupby(["prime_mover"])["age_in_report_year"].transform("mean"),
            )
            # recalc pollution control costs
            .assign(
                pollution_control_costs_per_kw=lambda x: x[
                    "real_pollution_control_costs_per_kw"
                ]
                / x["inflator_to_2021"]
            )
            .sort_values(
                by=["plant_id_eia", "generator_id", "report_date"], ascending=True
            )
            .query("prime_mover in @FOSSIL_PRIME_MOVER_MAP")
            .assign(report_year=lambda x: x.report_date.dt.year)
        )

        return self.core_validation(current, level="generator")
