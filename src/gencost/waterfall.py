import datetime
import logging
import shutil
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import pyarrow
import pyarrow.dataset as ds
from etoolbox.utils.pudl_helpers import (
    month_year_to_date,
    simplify_columns,
    sum_and_weighted_average_agg,
)
from etoolbox.utils.remote_zip import RemoteIOError, RemoteZip
from platformdirs import user_cache_path, user_documents_path
from tqdm.auto import tqdm
from tqdm.contrib.logging import logging_redirect_tqdm

from gencost.constants import FOSSIL_PRIME_MOVER_MAP, FUEL_GROUP_MAP
from gencost.crosswalk import Crosswalk
from gencost.package_data import PACKAGE_PATH

pat_path = Path(__file__).parent
CACHE_PATH = user_cache_path("gencost", "rmi")
logger = logging.getLogger(__name__)
FUEL_COLS = [
    "biofuel_mmbtu",
    "coal_mmbtu",
    "natural_gas_mmbtu",
    "other_mmbtu",
    "other_gas_mmbtu",
    "petroleum_mmbtu",
    "petroleum_coke_mmbtu",
]


def subplants_in_scenario_one(gen_923_by_subplant):
    """

    Make a list of sub-plant composite key that work in scenario #1,
    so we don't have to try to match them in scenario 2.

    """

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


def add_metrics(df):
    return df.assign(
        net_cf=lambda x: x.net_generation_mwh / (x.capacity_mw * 8760),
        net_hr=lambda x: x.fuel_consumed_for_electricity_mmbtu / x.net_generation_mwh,
    )


def filter_fuels(df):
    return (
        df[FUEL_COLS]
        .assign(other_net_mwh=lambda x: x.other_mmbtu + x.biofuel_mmbtu)
        .drop(columns=["biofuel_mmbtu"])
    )


def wage_data(
    years=(1994, 2023), clobber=False, base_url="https://data.bls.gov/cew/data/files/"
):
    """Download wage data for scaling cost data by year and state.

    Args:
        years: years of data that will be downloaded
        clobber: re-download data even if cached version exists
        base_url: base url to download from

    Returns:

    """
    par = CACHE_PATH / "wage_data.parquet"
    if par.exists() and not clobber:
        return pd.read_parquet(CACHE_PATH / "wage_data.parquet")
    else:
        path = CACHE_PATH / "temp"
        path.mkdir(parents=True, exist_ok=True)
        with logging_redirect_tqdm():
            for y in tqdm(range(*years), desc="Downloading wage data"):
                url = base_url + f"{y}/csv/{y}_annual_by_industry.zip"
                try:
                    with RemoteZip(url) as zipf:
                        file, *_ = (x for x in zipf.namelist() if " 2211 " in x)
                        zipf.extract(file, path / f"{y}.csv")
                except RemoteIOError:
                    logger.error("Unable to download wage data for %s from %s", y, url)

        data = (
            ds.dataset(
                path,
                format="csv",
                schema=pyarrow.schema(
                    {
                        "area_fips": pyarrow.string(),
                        "agglvl_code": pyarrow.int32(),
                        "year": pyarrow.int32(),
                        "annual_avg_emplvl": pyarrow.int64(),
                        "avg_annual_pay": pyarrow.int64(),
                    }
                ),
            )
            .to_table(filter=ds.field("agglvl_code") == 56)
            .to_pandas()
            .astype(
                {
                    "annual_avg_emplvl": "Int64",
                    "avg_annual_pay": "Float64",
                    "area_fips": "Int64",
                }
            )
        )
        data.to_parquet(par)
        shutil.rmtree(path)
        return data


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
        self.get_all_data_by_prime().query(expr).plant_id_eia.unique()
        return self.get_all_data_by_prime().query("plant_id_eia in @q")

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

    def merge_all(self, clean=True):
        if "merge_all" not in self._dfs:
            aggs = {
                "step": "first",
                "generator_starts": "sum",  # max?
                "fuel_starts": "sum",  # max?
                "subplant_id": pd.Series.unique,
            }
            index_cols = ["plant_id_eia", "pf_subplant_id", "report_date"]

            exa = self.get_exa_all()
            cost = self.get_cost_data_by_prime()
            ags = self.get_additional_generator_specs_by_x(
                subplant_id_col="pf_subplant_id"
            )

            merge_indicators = {
                "both,both": "both",
                "both,left_only": "no_ags",
                "left_only,both": "no_cost",
                "left_only,left_only": "no_cost_ags",
                "right_only,both": "no_exa",
                "right_only,left_only": "no_exa_ags",
                ",right_only": "no_exa_cost",
            }

            # aggregate all waterfall levels to prime for merging with cost
            exa_agg = exa.groupby(index_cols).agg(
                {col: aggs.get(col, "sum") for col in exa if col not in index_cols}
            )

            exa_cost = exa_agg.merge(
                cost,
                on=index_cols,
                how="outer",
                validate="1:1",
                indicator=True,
            ).rename(columns={"_merge": "exa_cost"})

            out = (
                exa_cost.merge(
                    ags,
                    on=["plant_id_eia", "pf_subplant_id"],
                    how="outer",
                    validate="m:1",
                    indicator=True,
                )
                .assign(
                    _merge=lambda x: x[["exa_cost", "_merge"]]
                    .astype(str)
                    .agg(",".join, axis=1)
                )
                .replace({"_merge": merge_indicators})
            )

            test = (
                out.query("_merge != 'both'")
                .groupby(["_merge", "report_date"])
                .plant_id_eia.nunique()
                .to_frame()
                .query("plant_id_eia > 0")
                .squeeze()
            )
            logger.warning(
                "Final merge stats, only those marked 'all' will be retained "
                "('+' means additional generator specs were available):\n %s \n",
                test.squeeze().to_dict(),
            )
            out = (
                out.query("_merge == 'both'")
                .assign(
                    hrs_in_yr=lambda x: np.where(
                        x.report_date.dt.is_leap_year, 8784, 8760
                    ),
                    net_cf=lambda x: x.net_generation_mwh
                    / (x.capacity_mw * x.hrs_in_yr),
                    net_hr=lambda x: x.fuel_consumed_for_electricity_mmbtu
                    / x.net_generation_mwh,
                    gross_cf=lambda x: x.gross_generation_mwh
                    / (x.capacity_mw * x.hrs_in_yr),
                    gross_hr=lambda x: x.heat_in_mmbtu / x.gross_generation_mwh,
                    parasitic_load_pct=lambda x: 1
                    - x.net_generation_mwh / x.gross_generation_mwh,
                    average_age_in_report_year=lambda x: (
                        x.report_date - x.operating_date
                    ).dt.days
                    / 365.25,
                    n_fuel_groups=lambda x: (x[FUEL_COLS] / x[FUEL_COLS].sum(axis=1))
                    .gt(0.02)
                    .sum(axis=1)
                    .astype("Int64"),
                    top_fuel_share=lambda x: filter_fuels(x).max(axis=1)
                    / x[FUEL_COLS].sum(axis=1),
                    top_fuel=lambda x: filter_fuels(x)
                    .idxmax(axis=1)
                    .str.replace("_mmbtu", ""),
                    true_multi_fuel="multi_fuel",
                    fuel_category=lambda x: x.true_multi_fuel.mask(
                        x.top_fuel_share >= 0.6,
                        "≥60% " + x.top_fuel,
                    ).mask(x.top_fuel_share >= 0.9, x.top_fuel),
                    # _age_cap=lambda x: x.age * x.capacity_mw,
                    # _age_prime_fuel_average=lambda x: x.groupby(
                    #     ["prime_mover", "top_fuel"]
                    # )._age_cap.transform("sum")
                    # / x.groupby(["prime_mover", "top_fuel"]).capacity_mw.transform(
                    #     "sum"
                    # ),
                    # age_relative_to_average2=lambda x: x.age
                    # - x._age_prime_fuel_average,
                )
                .drop(
                    columns=[
                        "_merge",
                        "hrs_in_yr",
                        "true_multi_fuel",
                        "exa_cost",
                        # "_age_cap",
                        # "_age_prime_fuel_average",
                    ]
                )
            )

            # add gross cfs by fuel group
            out[[x.replace("_mmbtu", "_gross_cf") for x in FUEL_COLS]] = (
                out[FUEL_COLS]
                .divide(out[FUEL_COLS].sum(axis=1), axis=0)
                .multiply(out.gross_generation_mwh, axis=0)
                .divide(
                    out.capacity_mw
                    * np.where(out.report_date.dt.is_leap_year, 8784, 8760),
                    axis=0,
                )
            )
            self._dfs["merge_all"] = out

        if clean:
            return (
                self._dfs["merge_all"]
                # numexpr / query cannot deal with nullable floats
                .astype({"parasitic_load_pct": float, "gross_cf": float})
                .query("0.0 < parasitic_load_pct < 100.0 & 0.0 <= gross_cf <= 1.5")
                .astype({"parasitic_load_pct": "Float64", "gross_cf": "Float64"})
                .copy()
            )

        return self._dfs["merge_all"]

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
            "capacity_mw": "Float64",
            "camd_capacity_mw": "Float64",
            "net_generation_mwh": "Float64",
            "fuel_consumed_for_electricity_mmbtu": "Float64",
            "generator_starts": "Int64",
            "fuel_starts": "Int64",
            "gross_generation_mwh": "Float64",
            "heat_in_mmbtu": "Float64",
        }
        return ppf_and_waterfall.astype(
            {k: "Float64" for k in ppf_and_waterfall} | types
        )[list(types) + [x for x in ppf_and_waterfall if x not in types]]

    def get_exa_by_prime(self):
        if "exa_by_prime" not in self._dfs:
            merged = self._exa_by_prime()

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

            non_zeros = out.sum(axis=0) != 0
            self._dfs["exa_by_prime"] = out.loc[
                :, [non_zeros.get(x, True) for x in out.columns]
            ]
        return self._dfs["exa_by_prime"]

    def _exa_by_prime(self):
        df_923 = self.get_gf923_by_prime()
        # cems data aggregated to ppf_subplant id
        df_cems = self.get_cems_by_x(subplant_id_col="pf_subplant_id")
        df_860 = self.get_860_by_x(subplant_id_col="pf_subplant_id")
        merged0 = df_860.merge(
            df_923,
            on=["plant_id_eia", "pf_subplant_id", "report_date"],
            validate="1:1",
            how="right",
            indicator=True,
        ).rename(columns={"_merge": "eia_merge"})
        merged = (
            merged0.merge(
                df_cems,
                on=["plant_id_eia", "pf_subplant_id", "report_date"],
                validate="1:1",
                how="outer",
                indicator=True,
            )
            .rename(columns={"_merge": "exa_merge"})
            .assign(
                _merge=lambda x: x[["eia_merge", "exa_merge"]]
                .astype("string")
                .fillna("")
                .agg(",".join, axis=1)
                .replace(
                    {
                        "both,both": "all",
                        "both,left_only": "eia_only",
                        "right_only,both": "923_epa",
                        ",right_only": "epa_only",
                    }
                )
            )
            .drop(columns=["eia_merge", "exa_merge"])
        )
        return merged

    def get_exa_by_subplant(self, by_fuel=True):
        """
        1) Complete waterfall step 1 by merging BF df to G 923 df
        2) Concat waterfall step 1 and 2 into single df
        3) Merge cems and 860 data in

        Returns:

        """
        if "waterfall" + str(by_fuel) not in self._dfs:
            # for both waterfall subsets
            df_860 = self.get_860_by_x(subplant_id_col="subplant_id")
            df_cems = self.get_cems_by_x(subplant_id_col="subplant_id")

            # waterfall step 1:
            df_gen923 = self.get_gen923_by_subplant()
            df_bf923 = self.get_bf923_by_subplant(by_fuel=by_fuel)

            # add fuel consummption data to make waterfall step one complete
            waterfall_step_one = df_gen923.merge(
                df_bf923,
                on=["plant_id_eia", "subplant_id", "report_date"],
                how="inner",
                validate="1:1",
            )

            if by_fuel:
                waterfall_step_one[
                    [
                        x.replace("_mmbtu", "_net_mwh")
                        for x in waterfall_step_one.filter(like="_mmbtu").columns
                    ]
                ] = (
                    waterfall_step_one.filter(like="_mmbtu")
                    .divide(
                        waterfall_step_one.filter(like="_mmbtu").sum(axis=1), axis=0
                    )
                    .multiply(waterfall_step_one.net_generation_mwh, axis=0)
                )
                waterfall_step_one = waterfall_step_one.assign(
                    fuel_consumed_for_electricity_mmbtu=lambda x: x.filter(
                        like="_mmbtu"
                    ).sum(axis=1)
                )

            # waterfall step 2:
            waterfall_step_two = self.get_gf923_by_subplant(
                # crosswalk with prime fuel from crosswalk class, used OGE version so
                # preserving that for now
                subplants_in_scenario_one(df_gen923),
                by_fuel=by_fuel,
            )

            # now that both waterfall steps have generation and fuel consumption,
            # let's concat them
            waterfall = pd.concat(
                [waterfall_step_one.assign(step=1), waterfall_step_two.assign(step=2)]
            ).sort_values(by=["plant_id_eia", "subplant_id", "report_date"])

            # merge cems and 860 data
            merged = (
                df_860.merge(
                    waterfall,
                    on=["plant_id_eia", "subplant_id", "report_date"],
                    validate="1:1",
                    how="right",
                    indicator=True,
                )
                .rename(columns={"_merge": "eia_merge"})
                .merge(
                    df_cems,
                    on=["plant_id_eia", "subplant_id", "report_date"],
                    validate="1:1",
                    how="outer",
                    indicator=True,
                )
                .rename(columns={"_merge": "exa_merge"})
                .assign(
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
                    )
                )
                .drop(columns=["exa_merge", "eia_merge"])
            )
            test = merged.groupby("_merge").plant_id_eia.nunique()
            logger.warning(
                "Final merge stats, only those marked 'all' will be retained from "
                "waterfall 1 and 2:\n %s \n",
                test.squeeze().to_dict(),
            )

            waterfall = merged.query("_merge == 'all'").drop(columns=["_merge"])
            non_zeros = waterfall.sum(axis=0) != 0
            self._dfs["waterfall" + str(by_fuel)] = waterfall.loc[
                :, [non_zeros.get(x, True) for x in waterfall.columns]
            ]
        return self._dfs["waterfall" + str(by_fuel)]

    def export_data_by_prime(self, name=None, clean=True):
        name = "data_for_pf_subplants.parquet" if name is None else name
        self.merge_all(clean=clean).drop(columns=["subplant_id"]).to_parquet(
            user_documents_path() / name
        )

    ###########################################################################
    # Check distribution of metrics
    ###########################################################################

    @property
    def parasitic_load_distribution(self):
        return (
            pd.value_counts(
                pd.cut(
                    self.get_all_data_by_prime().parasitic_load_pct,
                    [-1e4, -100, -5, -1, 0, 1, 5, 100, 1e4],
                )
            ).sort_index()
            / self.get_all_data_by_prime().parasitic_load_pct.count()
        )

    @property
    def gross_cf_distribution(self):
        return (
            pd.value_counts(
                pd.cut(
                    self.get_all_data_by_prime().gross_cf,
                    [-5, -1, -0.5, 0, 0.5, 1, 1.2, 5, 10],
                )
            ).sort_index()
            / self.get_all_data_by_prime().gross_cf.count()
        )

    @property
    def net_cf_distribution(self):
        return (
            pd.value_counts(
                pd.cut(
                    self.get_all_data_by_prime().net_cf,
                    [-5, -1, -0.5, 0, 0.5, 1, 1.2, 5, 10],
                )
            ).sort_index()
            / self.get_all_data_by_prime().net_cf.count()
        )

    @property
    def covered_generators(self):
        return self.safe_xwalk.copy().merge(
            self.get_all_data_by_prime()
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

        fig = px.scatter(
            result,
            **{
                "capacity": {"x": "capacity_mw", "y": "camd_capacity_mw"},
                "energy": {"x": "net_generation_mwh", "y": "gross_generation_mwh"},
                "cf": {"x": "net_cf", "y": "gross_cf"},
            }[comparison],
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
    ):
        return px.ecdf(
            self.merge_all(clean=clean),
            x=x,
            markers=True,
            color=color,
            facet_col=facet_col,
            facet_row=facet_row,
            marginal=marginal,
        )

    def draw_capacity_ecdf(
        self,
        facet_col="prime_mover",
        facet_row=None,
        clean=True,
        ecdfnorm="probability",
        ecdfmode="standard",
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
            .assign(
                prime_mover=lambda x: x.prime_mover_code.replace(
                    FOSSIL_PRIME_MOVER_MAP
                ),
                year=lambda x: x.report_date.dt.year,
            )[["plant_id_eia", "generator_id", "year", "prime_mover", "capacity_mw"]]
        )
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            cems = (
                self.get_cems()
                .merge(
                    self.xwalk.dropna(
                        axis=0, subset=["plant_id_epa", "emissions_unit_id_epa"]
                    ),
                    on=["plant_id_epa", "emissions_unit_id_epa"],
                    how="inner",
                    validate="m:m",
                )[["plant_id_eia", "generator_id"]]
                .drop_duplicates()
            )
        cems_covered = df860.merge(
            cems,
            on=["plant_id_eia", "generator_id"],
            how="inner",
            validate="m:1",
        ).assign(series="cems_matched")
        ppf_covered = df860.merge(
            self.xwalk.merge(
                self.merge_all(clean=False)[
                    ["plant_id_eia", "pf_subplant_id"]
                ].drop_duplicates(),
                on=["plant_id_eia", "pf_subplant_id"],
                how="inner",
                validate="m:1",
            )[["plant_id_eia", "generator_id"]].drop_duplicates(),
            on=["plant_id_eia", "generator_id"],
            how="inner",
            validate="m:1",
        ).assign(series="final_merge")
        ppf_clean = df860.merge(
            self.xwalk.merge(
                self.merge_all(clean=True)[
                    ["plant_id_eia", "pf_subplant_id"]
                ].drop_duplicates(),
                on=["plant_id_eia", "pf_subplant_id"],
                how="inner",
                validate="m:1",
            )[["plant_id_eia", "generator_id"]].drop_duplicates(),
            on=["plant_id_eia", "generator_id"],
            how="inner",
            validate="m:1",
        ).assign(series="cleaned")
        very_clean = df860.merge(
            self.xwalk.merge(
                self.merge_all(clean=True)
                .assign(max_gross=lambda x: np.where(x.net_cf > 0, x.net_cf * 1.5, 1))
                .astype({"gross_cf": float, "net_cf": float, "max_gross": float})
                .query("gross_cf > net_cf & gross_cf < max_gross")[
                    ["plant_id_eia", "pf_subplant_id"]
                ]
                .drop_duplicates(),
                on=["plant_id_eia", "pf_subplant_id"],
                how="inner",
                validate="m:1",
            )[["plant_id_eia", "generator_id"]].drop_duplicates(),
            on=["plant_id_eia", "generator_id"],
            how="inner",
            validate="m:1",
        ).assign(series="very_clean")
        result = pd.concat(
            [
                df860.assign(series="860"),
                cems_covered,
                ppf_covered,
                ppf_clean,
                very_clean,
            ]
        )
        return result

    ###########################################################################
    # Aggregate source data to subplant levels
    ###########################################################################

    def get_860_by_x(self, subplant_id_col="pf_subplant_id", merge_only=False):
        """
        Map capacity and sum to plant prime fuel subplant level

        """
        xwalk = {"pf_subplant_id": self.safe_xwalk, "subplant_id": self.xwalk}[
            subplant_id_col
        ]
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
                xwalk[
                    ["plant_id_eia", "generator_id", subplant_id_col]
                ].drop_duplicates(),
                on=["plant_id_eia", "generator_id"],
                how="outer",
                validate="m:1",
                indicator=True,
            )
        )
        test = (
            merged.query(
                "_merge != 'both' & prime_mover_code in @FOSSIL_PRIME_MOVER_MAP"
            )
            .replace(
                {"_merge": {"left_only": "in_data_only", "right_only": "in_xwalk_only"}}
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
        }
        return (
            merged.query("_merge == 'both'")
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
                sum_cols=["capacity_mw"],
                wtavg_dict=wtavg_dict,
            )
            .astype({"plant_id_eia": "Int64", subplant_id_col: "Int64"})
        )
        # return (
        #     merged.query("_merge == 'both'")
        #     .drop(columns=["_merge"])
        #     .groupby(
        #         [
        #             "plant_id_eia",
        #             subplant_id_col,
        #             pd.Grouper(key="report_date", freq="YS"),
        #         ]
        #     )
        #     .capacity_mw.sum()
        #     .reset_index()
        #     .astype({"plant_id_eia": "Int64", subplant_id_col: "Int64"})
        # )

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

    def get_bf923_by_subplant(self, merge_only=False, by_fuel=False):
        """
        Args:
            by_fuel: pivot by fuel group
            merge_only:

        transform BF 923
        1) make year and unit id pudl as it is in bf table
        2) merge with grand crosswalk on unit id pudl, drop na's they mess up m:1 check
        3) roll up to subplant level



        """

        merged = (
            self.pudl_tabl.bf_eia923()
            .assign(fuel_group=lambda x: x.energy_source_code.map(FUEL_GROUP_MAP))
            .merge(
                self.xwalk.query("unit_id_pudl.notnull()")[
                    ["plant_id_eia", "unit_id_pudl", "subplant_id"]
                ].drop_duplicates(),
                on=["plant_id_eia", "unit_id_pudl"],
                how="outer",
                validate="m:1",
                indicator=True,
            )
        )

        test = (
            merged.query("_merge != 'both' ")
            .replace(
                {"_merge": {"left_only": "in_data_only", "right_only": "in_xwalk_only"}}
            )
            .groupby(["_merge", "prime_mover_code"])
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
        if by_fuel:
            out = (
                merged.query("_merge == 'both'")
                .rename(
                    columns={
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
                    values=["mmbtu"],
                    aggfunc="sum",
                )
                .reorder_levels([1, 0], axis=1)
            )
            out.columns = map("_".join, out.columns)
            return out.loc[:, out.sum(axis=0) != 0].reset_index()

        return (
            merged.query("_merge == 'both'")
            .drop(columns=["_merge"])
            .groupby(
                [
                    "plant_id_eia",
                    "subplant_id",
                    pd.Grouper(key="report_date", freq="YS"),
                ],
                dropna=False,
            )["fuel_consumed_units"]
            .sum()
            .reset_index()
        )

    def get_gf923_by_subplant(self, scenario_one_subplants, by_fuel=False):
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
            .assign(
                report_year=lambda x: x.report_date.dt.year,
                # moving this up top to allow CC matches
                prime_mover=lambda x: x.prime_mover_code.replace(
                    FOSSIL_PRIME_MOVER_MAP
                ),
            )
            # .rename(columns={"prime_mover_code": "prime_mover"})
            .merge(
                pf_crosswalk[["plant_id_eia", "subplant_id", "prime_mover"]],
                on=["plant_id_eia", "prime_mover"],
                how="outer",
                validate="m:1",
                indicator=True,
            )
            .dropna(subset="report_year")
        )
        (
            df.query("_merge != 'both' & prime_mover in @FOSSIL_PRIME_MOVER_MAP")
            .replace(
                {"_merge": {"left_only": "in_data_only", "right_only": "in_xwalk_only"}}
            )
            .groupby(["_merge", "prime_mover"], dropna=False)
            .plant_id_eia.nunique()
            .to_frame()
            .query("plant_id_eia > 0")
        )

        logger.warning(
            "Waterfall subset 2: Subplant groups that are not the single and only "
            "prime mover within their plant are being dropped",
        )
        if by_fuel:
            out = (
                df.assign(
                    fuel_group=lambda x: x.energy_source_code.replace(FUEL_GROUP_MAP),
                )
                .rename(
                    columns={
                        "fuel_consumed_for_electricity_mmbtu": "mmbtu",
                        "net_generation_mwh": "net_mwh",
                    }
                )
                .pivot_table(
                    index=[
                        "plant_id_eia",
                        "subplant_id",
                        pd.Grouper(key="report_date", freq="YS"),
                    ],
                    columns="fuel_group",
                    values=["mmbtu", "net_mwh"],
                    aggfunc="sum",
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
                    fuel_consumed_for_electricity_mmbtu=lambda x: x.filter(
                        like="_mmbtu"
                    ).sum(axis=1),
                    net_generation_mwh=lambda x: x.filter(like="_net_mwh").sum(axis=1),
                )
                .query("plant_subplant_year_eia not in @scenario_one_subplants")
                .drop(columns=["plant_subplant_year_eia", "year"])
            )

        return (
            df.groupby(
                [
                    "plant_id_eia",
                    "subplant_id",
                    pd.Grouper(key="report_date", freq="YS"),
                ]
            )[["net_generation_mwh", "fuel_consumed_for_electricity_mmbtu"]]
            .sum()
            .reset_index()
            .assign(
                year=lambda x: x["report_date"].dt.year,
                plant_subplant_year_eia=lambda x: x[
                    ["plant_id_eia", "subplant_id", "year"]
                ]
                .astype(str)
                .agg("_".join, axis=1),
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
        merged = (
            self.pudl_tabl.gf_eia923()
            .assign(
                # report_year=lambda x: x.report_date.dt.year,
                prime_mover=lambda x: x.prime_mover_code.replace(
                    FOSSIL_PRIME_MOVER_MAP
                ),
                fuel_group=lambda x: x.energy_source_code.replace(FUEL_GROUP_MAP),
            )
            .rename(
                columns={
                    "fuel_consumed_for_electricity_mmbtu": "mmbtu",
                    "net_generation_mwh": "net_mwh",
                }
            )
            .pivot_table(
                index=["plant_id_eia", "prime_mover", "report_date"],
                columns="fuel_group",
                values=["mmbtu", "net_mwh"],
                aggfunc="sum",
            )
            .reorder_levels([1, 0], axis=1)
        )
        merged.columns = map("_".join, merged.columns)
        merged = merged.reset_index().merge(
            self.safe_xwalk[
                ["plant_id_eia", "pf_subplant_id", "prime_mover"]
            ].drop_duplicates(),
            on=["plant_id_eia", "prime_mover"],
            how="outer",
            validate="m:1",
            indicator=True,
        )
        test = (
            merged.query("_merge != 'both' & prime_mover in @FOSSIL_PRIME_MOVER_MAP")
            .replace(
                {"_merge": {"left_only": "in_data_only", "right_only": "in_xwalk_only"}}
            )
            .groupby(["_merge", "prime_mover"])
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
            .assign(
                net_generation_mwh=lambda x: x.filter(like="_net_mwh").sum(axis=1),
                fuel_consumed_for_electricity_mmbtu=lambda x: x.filter(
                    like="_mmbtu"
                ).sum(axis=1),
            )
        )

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
            xwalk = self.safe_xwalk

        merged = self.get_cems().merge(
            self.safe_xwalk[
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
            .replace(
                {"_merge": {"left_only": "in_data_only", "right_only": "in_xwalk_only"}}
            )
            .groupby(["_merge", pd.Grouper(key="report_date", freq="YS")], dropna=False)
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
            # "heat_in_mmbtu_max": "sum",  # don't think we need this
            # "co2_tons_max": "sum",  # don't think we need this
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

    def get_additional_generator_specs_by_x(
        self, merge_only=False, subplant_id_col="pf_subplant_id"
    ):
        col_info = pd.read_csv(PACKAGE_PATH / "coi_col_info.csv", index_col=0).assign(
            agg_method_r=lambda x: x.agg_method.replace(
                {"cap_wt_avg": "sum", "mode": mode}
            )
        )

        coi = (
            pd.read_parquet(PACKAGE_PATH / "unit_level_costs_with_flag.parquet.gzip")
            .rename(
                columns=col_info.old_names.reset_index()
                .set_index("old_names")
                .dropna()
                .squeeze()
                .to_dict()
            )
            .pipe(month_year_to_date)
            .assign(
                age=lambda x: (datetime.datetime.now() - x.operating_date),
                td_retirement=lambda x: datetime.datetime.now() - x.retirement_date,
                td_planned_retirement=lambda x: datetime.datetime.now()
                - x.planned_retirement_date,
            )
            .astype(col_info.new_type.dropna().to_dict())
        )
        merged = (
            self.safe_xwalk[["plant_id_eia", "generator_id", subplant_id_col]]
            .drop_duplicates()
            .merge(
                coi,
                on=["plant_id_eia", "generator_id"],
                how="outer",
                validate="1:1",
                indicator=True,
            )
        )
        test = merged.groupby(["_merge"]).plant_id_eia.nunique()
        logger.warning(
            "AGS %s: Unique plants that did not have matches in both "
            "additional generator specs and the xwalk so will be dropped:\n %s \n",
            {"pf_subplant_id": "prime", "subplant_id": "subplant"}[subplant_id_col],
            test.squeeze().to_dict(),
        )
        if merge_only:
            return merged
        merged = merged.query("_merge == 'both'").drop(columns=["_merge"])
        cap_wt_cols = list(
            col_info[["agg_method"]].dropna().query("agg_method == 'cap_wt_avg'").index
        )
        round_cols = list(col_info[["round"]].dropna().index)
        merged.loc[:, round_cols] = merged.loc[:, round_cols].fillna(0)
        merged.loc[:, cap_wt_cols] = merged.loc[:, cap_wt_cols].multiply(
            (
                merged["operational_capacity_in_report_year"]
                / merged.groupby(
                    ["plant_id_eia", subplant_id_col]
                ).operational_capacity_in_report_year.transform("sum")
            ),
            axis=0,
        )

        out = (
            merged.groupby(["plant_id_eia", subplant_id_col])
            .agg(col_info.agg_method_r.dropna().to_dict())
            .assign(
                operating_date=lambda x: (datetime.datetime.now() - x.age).dt.floor(
                    freq="D", ambiguous="infer"
                ),
                retirement_date=lambda x: (
                    datetime.datetime.now()
                    - x.td_retirement.replace({pd.Timedelta(0): pd.NaT})
                ).dt.floor(freq="D", ambiguous="infer"),
                planned_retirement_date=lambda x: (
                    datetime.datetime.now()
                    - x.td_planned_retirement.replace({pd.Timedelta(0): pd.NaT})
                ).dt.floor(freq="D", ambiguous="infer"),
                age=lambda x: x.age.dt.days / 365,
            )
            .reset_index()
            .drop(columns=["td_retirement", "td_planned_retirement"])
            .astype({"plant_id_eia": "Int64", subplant_id_col: "Int64"})
        )
        # Rounding these columns to bring back the binary original might not be the
        # right choice for the regression and can always be done later
        # out.loc[:, round_cols] = out.loc[:, round_cols].round().astype("Int64")
        return out

    def get_cost_data_by_prime(self):
        dtypes = {
            "plant_id_eia": "Int64",
            "prime_mover": "string",
            "report_date": "datetime64[ns]",
            "state": "string",
            "fuel_1": "string",
            "fuel_2": "string",
            "fuel_3": "string",
        }
        cost = pd.read_parquet(
            PACKAGE_PATH / "860_FERC_matching_cost_regressions.parquet.gzip",
        )

        cost = (
            cost.assign(report_month=1)
            .pipe(month_year_to_date)
            .pipe(simplify_columns)
            .rename(columns={"plant": "plant_id_eia", "prime": "prime_mover"})
            # .drop(columns=["cc", "gt", "ic", "ot", "st"])
        )
        fuel_counts = cost.groupby(
            ["plant_id_eia", "prime_mover", "report_date"]
        ).fuel_1.count()
        logger.warning(
            "FERC: number of unique plant_ids for each prime mover that had multiple "
            "plant/prime/year rows:\n %s\n",
            cost.set_index(["plant_id_eia", "prime_mover", "report_date"])
            .loc[fuel_counts[fuel_counts != 1].index, :]
            .reset_index()
            .groupby("prime_mover")
            .plant_id_eia.nunique()
            .to_dict(),
        )

        to_merge = (
            cost.set_index(["plant_id_eia", "prime_mover", "report_date"])
            .loc[fuel_counts[fuel_counts == 1].index, :]
            .reset_index()
            .astype(dtypes | {x: "Float64" for x in cost.columns if x not in dtypes})
            .merge(
                self.get_wage_scale(),
                on=["report_date", "state"],
                how="left",
                validate="m:1",
            )
            .fillna({"wage_scale": 1})
        )

        merged = to_merge.merge(
            self.safe_xwalk[
                ["plant_id_eia", "pf_subplant_id", "prime_mover"]
            ].drop_duplicates(),
            on=["plant_id_eia", "prime_mover"],
            how="outer",
            validate="m:1",
            indicator=True,
        ).astype({"pf_subplant_id": "Int64"})
        test = (
            merged.query("_merge != 'both' & prime_mover in @FOSSIL_PRIME_MOVER_MAP")
            .replace(
                {"_merge": {"left_only": "in_data_only", "right_only": "in_xwalk_only"}}
            )
            .groupby(["_merge", "prime_mover"])
            .plant_id_eia.nunique()
            .to_frame()
            .query("plant_id_eia > 0")
        )
        logger.warning(
            "FERC Costs: Unique plants that did not have matches in both FERC and the "
            "xwalk so will be dropped:\n %s \n",
            test.squeeze().to_dict(),
        )
        return merged.query("_merge == 'both'")[
            [
                "pf_subplant_id",
                "plant_id_eia",
                "report_date",
                "ferc_cf",
                "operating_capacity_in_report_year",
                "capacity_of_currently_operating_units",
                "average_age_in_report_year",
                "age_of_observation",
                "current_average_age",
                # "prime_fuels_average_age",
                "age_relative_to_average",
                "real_opex_percentile",
                "real_capex_percentile",
                "cf_relative_to_average",
                "real_opex_per_kw",
                "real_capex_per_kw",
                "real_opex",
                "real_capex",
                "inflator_to_2021",
                "wage_scale",
                "natural_gas",
                "coal",
                "petroleum",
                "petroleum_coke",
                "other_gas",
                "cc",
                "gt",
                "ic",
                "ot",
                "st",
                # "extraordinary_expense",
                "maintenance_capex",
                # "interim_retirements",
                "real_maintenance_capex",
                # "real_interim_retirements",
                # "arc_per_kw",
            ]
        ]

    def get_wage_scale(self):
        fip = pd.read_csv(PACKAGE_PATH / "State_FIPS_Match.csv")
        return (
            wage_data()
            .assign(total_wages=lambda x: x.avg_annual_pay * x.annual_avg_emplvl)
            .groupby(["area_fips", "year"])[["annual_avg_emplvl", "total_wages"]]
            .sum()
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
            )
            .rename(columns={"year": "report_year"})
            .dropna(subset="state")
            .pipe(month_year_to_date)[["report_date", "state", "wage_scale"]]
        )
