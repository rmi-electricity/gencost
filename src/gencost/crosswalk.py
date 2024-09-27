import logging
import warnings

import networkx as nx
import numpy as np
import pandas as pd
from etoolbox.utils.pudl import pd_read_pudl

from gencost.constants import (
    FOSSIL_PRIME_MOVER_MAP,
    FUEL_GROUP_MAP,
    PUDL_RELEASE_VERSION,
    UDAY_FOSSIL_FUEL_MAP,
)

LOGGER = logging.getLogger(__name__)


# from pudl
def _prep_for_networkx(
    crosswalk: pd.DataFrame,
    source_keys: list[str],
    source_name: str,
    target_keys: list[str],
    target_name: str,
) -> pd.DataFrame:
    """Make surrogate keys for gen prime fuel and subplant generator.
    Args:
        crosswalk: crosswalk with prime fuel
        source_keys: columns that comprise the source composite key
        source_name: name of the source composite key column
        target_keys: columns that comprise the target composite key
        target_name: name of the target composite key column
    Returns:
        pd.DataFrame: copy of crosswalk with prime fuel with new surrogate ID columns
            'prime_fuel' and 'subplant_gen'
    """
    prepped = crosswalk.copy()
    # networkx can't handle composite keys, so make surrogates
    prepped[source_name] = prepped.groupby(by=source_keys).ngroup()
    # node IDs can't overlap so add (max + 1)
    prepped[target_name] = (
        prepped.groupby(by=target_keys).ngroup() + prepped[source_name].max() + 1
    )
    return prepped


# from pudl
def _subplant_ids_from_prepped_crosswalk(
    prepped: pd.DataFrame, source_name: str, target_name: str, new_key_name: str
) -> pd.DataFrame:
    """Use networkx graph analysis to create prime fuel subplant IDs from crosswalk
    edge list.

    Args:
        prepped: crosswalk with prime fuel passed through
            _prep_for_networkx()
        source_name: name of the source composite key column
        target_name: name of the target composite key column
        new_key_name: name of the new id/key column
    Returns:
        pd.DataFrame: copy of prime fuel crosswalk plus new column 'global_subplant_id'
    """
    graph = nx.from_pandas_edgelist(
        prepped,
        source=source_name,
        target=target_name,
        edge_attr=True,
    )
    for i, node_set in enumerate(nx.connected_components(graph)):
        subgraph = graph.subgraph(node_set)
        if not nx.algorithms.bipartite.is_bipartite(subgraph):
            raise AssertionError(f"non-bipartite: i={i}, node_set={node_set}")
        nx.set_edge_attributes(subgraph, name="global_" + new_key_name, values=i)
    return nx.to_pandas_edgelist(graph)


# from pudl
def _convert_global_id_to_composite_id(
    crosswalk_with_ids: pd.DataFrame, new_key_name: str
) -> pd.DataFrame:
    """Convert global_subplant_id to a composite key (plant_id_eia, pf_subplant_id).
    The composite key will be much more stable (though not fully stable!) in time.
    The global ID changes if ANY unit or generator changes, whereas the
    compound key only changes if units/generators change within that specific plant.
    A global ID could also tempt users into using it as a crutch, even though it isn't
    stable. A compound key should discourage that behavior.
    Args:
        crosswalk_with_ids: crosswalk with pf_subplant_id, as from
            _subplant_ids_from_prepped_crosswalk()
        new_key_name: name of the new id/key column

    Raises:
        ValueError: if crosswalk_with_ids has a MultiIndex
    Returns:
        pd.DataFrame: copy of crosswalk_with_ids with an added column: 'pf_subplant_id'
    """
    if isinstance(crosswalk_with_ids.index, pd.MultiIndex):
        raise ValueError(
            f"Input crosswalk must have single level index. "
            f"Given levels: {crosswalk_with_ids.index.names}"
        )

    reindexed = crosswalk_with_ids.reset_index()  # copy
    idx_name = crosswalk_with_ids.index.name
    if idx_name is None:
        # Indices with no name (None) are set to a pandas default name ('index'), which
        # could (though probably won't) change.
        idx_col = reindexed.columns.symmetric_difference(crosswalk_with_ids.columns)[
            0
        ]  # get index name
    else:
        idx_col = idx_name

    composite_key: pd.Series = reindexed.groupby("plant_id_eia", as_index=False).apply(
        lambda x: x.groupby("global_" + new_key_name).ngroup()
    )

    # Recombine. Could use index join but I chose to reindex, sort and assign.
    # Errors like mismatched length will raise exceptions, which is good.

    # drop the outer group, leave the reindexed row index
    composite_key.reset_index(level=0, drop=True, inplace=True)
    composite_key.sort_index(inplace=True)  # put back in same order as reindexed
    reindexed[new_key_name] = composite_key
    # restore original index
    reindexed.set_index(idx_col, inplace=True)  # restore values
    reindexed.index.rename(idx_name, inplace=True)  # restore original name
    return reindexed


# from pudl
def filter_crosswalk(crosswalk: pd.DataFrame, epacems: pd.DataFrame) -> pd.DataFrame:
    """Remove unmapped crosswalk rows or duplicates due to m2m boiler relationships.

    Args:
        crosswalk (pd.DataFrame): The epacamd_eia crosswalk.
        epacems (Union[pd.DataFrame, dd.DataFrame]): Emissions data. Must contain
            columns named ["plant_id_eia", "emissions_unit_id_epa"]

    Returns:
        pd.DataFrame: A filtered copy of epacamd_eia crosswalk
    """
    # Remove rows that represent graph edges between generators and boilers
    filtered_crosswalk = crosswalk.drop_duplicates(
        subset=["plant_id_eia", "emissions_unit_id_epa", "generator_id"]
    )
    # This is essentially an empirical filter on EPA units. Instead of filtering by
    # construction/retirement dates in the crosswalk (thus assuming they are accurate),
    # use the presence/absence of CEMS data to filter the units.
    unique_epacems_ids = epacems[
        ["plant_id_eia", "emissions_unit_id_epa"]
    ].drop_duplicates()
    key_map = unique_epacems_ids.merge(
        filtered_crosswalk,
        on=["plant_id_eia", "emissions_unit_id_epa"],
        how="inner",
    )
    return key_map


# from pudl
def make_subplant_ids(
    crosswalk: pd.DataFrame,
    source_keys: list[str],
    source_name: str,
    target_keys: list[str],
    target_name: str,
    new_key_name: str,
) -> pd.DataFrame:
    """Identify prime fuel sub-plants in the EPA/EIA crosswalk and EIA 860 graph.
    Any row filtering should be done before this step.
    Usage Example:
    epacems = pudl.output.epacems.epacems(states=['ID']) # small subset for quick test
    epacamd_eia = pudl_out.epacamd_eia()
    filtered_crosswalk = filter_crosswalk(epacamd_eia, epacems)
    crosswalk_with_subplant_ids = make_subplant_ids(filtered_crosswalk)
    Note that sub-plant ids should be used in conjunction with `plant_id_eia` vs.
    `plant_id_epa` because the former is more granular and integrated into CEMS during
    the transform process.

    Args:
        crosswalk (pd.DataFrame): The epacamd_eia crosswalk
        source_keys: columns that comprise the source composite key
        source_name: name of the source composite key column
        target_keys: columns that comprise the target composite key
        target_name: name of the target composite key column
        new_key_name: name of the new subplant column that makes up a
            composite key with plant_id_eia
    Returns:
        pd.DataFrame: An edge list connecting EPA units to EIA generators, with
            connected pieces issued a subplant_id
    """

    edge_list = _prep_for_networkx(
        crosswalk,
        source_keys=source_keys,
        target_keys=target_keys,
        source_name=source_name,
        target_name=target_name,
    )
    edge_list = _subplant_ids_from_prepped_crosswalk(
        edge_list,
        source_name=source_name,
        target_name=target_name,
        new_key_name=new_key_name,
    )
    edge_list = _convert_global_id_to_composite_id(edge_list, new_key_name=new_key_name)
    return edge_list


def harmonize_eia_epa_orispl(
    df: pd.DataFrame,
    crosswalk_df: pd.DataFrame,
) -> pd.DataFrame:
    """Harmonize the ORISPL code to match the EIA data.

    The EIA plant IDs and CEMS ORISPL codes almost match, but not quite. EPA has
    compiled a crosswalk that maps one set of IDs to the other. The crosswalk is
    integrated into the PUDL db.

    This function merges the crosswalk with the cems data thus adding the official
    plant_id_eia column to CEMS. In cases where there is no plant_id_eia value for a
    given plant_id_epa (i.e., this plant isn't in the crosswalk yet), we use
    fillna() to add the plant_id_epa value to the plant_id_eia column. Because the
    plant_id_epa is almost always correct this is reasonable.

    EIA IDs are more correct so use the crosswalk to fix any erronious EPA IDs and get
    rid of that column to avoid confusion.

    https://github.com/USEPA/camd-eia-crosswalk

    Note that this transformation needs to be run *before* convert_to_utc, because
    convert_to_utc uses the plant ID to look up timezones.

    Args:
        df: A CEMS hourly dataframe for one year-month-state.
        crosswalk_df: The epacamd_eia dataframe from the database.

    Returns:
        The same data, with the ORISPL plant codes corrected to match the EIA plant IDs.
    """
    # Make sure the crosswalk does not have multiple plant_id_eia values for each
    # plant_id_epa and emissions_unit_id_epa value before reassigning IDs.
    one_to_many = crosswalk_df.groupby(
        ["plant_id_epa", "emissions_unit_id_epa"]
    ).filter(lambda x: x.plant_id_eia.nunique() > 1)

    if not one_to_many.empty:
        raise AssertionError(
            "The epacamd_eia crosswalk has more than one plant_id_eia value per "
            "plant_id_epa and emissions_unit_id_epa group"
        )
    crosswalk_df = crosswalk_df[
        ["plant_id_eia", "plant_id_epa", "emissions_unit_id_epa"]
    ].drop_duplicates()

    # Merge CEMS with Crosswalk to get correct EIA ORISPL code and fill in all unmapped
    # values with old plant_id_epa value.
    df_merged = pd.merge(
        df,
        crosswalk_df,
        on=["plant_id_epa", "emissions_unit_id_epa"],
        how="left",
    ).assign(plant_id_eia=lambda x: x.plant_id_eia.fillna(x.plant_id_epa))

    return df_merged


class Crosswalk:
    def __init__(self, pudl_tabl=None, clobber=False):
        df = pd_read_pudl(
            "core_epa__assn_eia_epacamd_subplant_ids", release=PUDL_RELEASE_VERSION
        )
        # see https://github.com/catalyst-cooperative/pudl/issues/2548#issuecomment-1530735429
        fixes = [
            (2708, "2A", "2"),
            (2708, "2B", "2"),
            (4042, "3", "2"),
            (55126, "CT02", "CA02"),
        ]
        for pid, to_gen, from_gen in fixes:
            replacement = df.loc[
                (df.plant_id_eia == pid) & (df.generator_id == from_gen),
                "subplant_id",
            ]
            if isinstance(replacement, pd.Series) and len(replacement.unique()) == 1:
                replacement = replacement.unique()[0]
            if not isinstance(replacement, np.int64 | np.int32 | int):
                raise AssertionError(
                    f"Replacement subplant_id for ({pid=}, {to_gen=}) from "
                    f"({pid=}, {from_gen=}) is not int-like"
                )
            df.loc[
                (df.plant_id_eia == pid) & (df.generator_id == to_gen),
                "subplant_id",
            ] = replacement
        df = df.loc[~df.plant_id_eia.isin((55375,)), :]

        self.base_xwalk = df

        # also need to get rid of proposed generators that will muck up the processes
        self.xwalk_w_pf = self.get_crosswalk_with_prime_fuel(self.base_xwalk).query(
            "generator_operating_date.notna()"
        )
        self._grand_xwalk = self._prep_grand_xwalk()

    @property
    def grand_crosswalk(self):
        warnings.warn(
            "This crosswalk is not safe, it may have `pf_subplants with multiple "
            "primes. Use `safe_xwalk` instead.",
            UserWarning,
            stacklevel=2,
        )
        return self._grand_xwalk

    def multiprime(self, subplant_id_col):
        return self._grand_xwalk.assign(
            pm_count=lambda x: x.groupby(
                ["plant_id_eia", subplant_id_col]
            ).prime_mover.transform(pd.Series.nunique)
        ).query("pm_count > 1")

    @property
    def safe_xwalk(self):
        return self._grand_xwalk[self._grand_xwalk.single_prime]

    def _prep_grand_xwalk(self):
        edgelist = make_subplant_ids(
            self.xwalk_w_pf,
            source_keys=[
                "plant_id_eia",
                "prime_mover",
                # "fuel_group"
            ],
            target_keys=["plant_id_eia", "subplant_id"],
            source_name="plant_prime_fuel_id",
            target_name="subplant_generator_id_unique",
            new_key_name="pf_subplant_id",
        ).astype(
            {
                "plant_id_eia": int,
                "subplant_id": int,
                "pf_subplant_id": int,
                "generator_operating_date": "datetime64[ns]",
            }
        )

        def safe_test_func(x):
            return not (len(x.unique()) > 1 and np.any(x.isna()))

        def safe_prime(x):
            return len(x.unique()) == 1

        out = self.xwalk_w_pf.merge(
            edgelist[
                ["plant_id_eia", "subplant_id", "pf_subplant_id"]
            ].drop_duplicates(),
            on=["plant_id_eia", "subplant_id"],
            how="left",
            validate="m:1",
        )[
            [
                "plant_id_eia",
                "generator_id",
                "emissions_unit_id_epa",
                "subplant_id",
                "pf_subplant_id",
                "prime_mover",
                "fuel_group",
                "unit_id_pudl",
                "capacity_xwalk",
                # "retirement_date",
                "generator_operating_date",
                "plant_id_epa",
                "ppf",
            ]
        ].assign(
            single_prime=lambda x: x.groupby(
                ["plant_id_eia", "pf_subplant_id"]
            ).prime_mover.transform(safe_prime),
        )
        safe_test = out.groupby(
            ["plant_id_eia", "pf_subplant_id"]
        ).plant_id_epa.transform(safe_test_func)
        assert (  # noqa: S101
            safe_test.all()
        ), f"EPA IDs are unsafe {out[~safe_test].to_dict()}"
        return out

    def get_crosswalk_with_prime_fuel(self, oge_xwalk):
        """Transformations:
            1) convert CT and CA to CC
            2) make duplicate rows for energy source code
            3) convert fuel to fuel_group
            4) only plant prime fuels that are in 860
            5) only plant prime fuels that are in 923

        Returns:

        """
        eia_860 = (
            pd_read_pudl("_out_eia__yearly_generators", release=PUDL_RELEASE_VERSION)
            .query("prime_mover_code.notnull() ")
            .sort_values(["plant_id_eia", "generator_id", "report_date"])
            .assign(
                prime_mover_=lambda x: x["prime_mover_code"].replace(
                    FOSSIL_PRIME_MOVER_MAP
                ),
                # because some of these can change over time, want to make sure we get
                # the most recent and only the most recent value
                prime_mover=lambda x: x.groupby(
                    ["plant_id_eia", "generator_id"]
                ).prime_mover_.transform("last"),
                capacity_xwalk=lambda x: x.groupby(
                    ["plant_id_eia", "generator_id"]
                ).capacity_mw.transform("last"),
                generator_operating_date=lambda x: x.groupby(
                    ["plant_id_eia", "generator_id"]
                ).generator_operating_date.transform("last"),
            )
            .melt(
                id_vars=[
                    "plant_id_eia",
                    "generator_id",
                    "prime_mover",
                    "generator_operating_date",
                    "capacity_xwalk",
                ],
                value_vars=[f"energy_source_code_{x}" for x in range(1, 7)],
                value_name="fuel",
                var_name="energy_source_code_n",
            )
            .query(
                "fuel.notnull() "
                # "& fuel in @UDAY_FOSSIL_FUEL_MAP"
            )
            .assign(
                fuel_group=lambda x: x.fuel.replace(FUEL_GROUP_MAP),
            )
            .drop_duplicates(
                ["plant_id_eia", "generator_id", "prime_mover", "fuel_group"]
            )
            .assign(
                ppf=lambda x: x[["plant_id_eia", "prime_mover", "fuel_group"]]
                .astype(str)
                .agg("_".join, axis=1)
            )
        )

        # create dataframe bringing things together
        return oge_xwalk.merge(
            eia_860,  # .query("ppf in @prime_fuel923"),
            on=["plant_id_eia", "generator_id"],
            how="left",
            validate="m:m",
        )

    def make_comp_key(self):
        """Transform OGE's crosswalk.

        based on assumptions that
        1) we only care about when we have info from both EPA and EIA sides are
            filled in, and that the pair we care about is plant plant subplant id
        2) have to clean gen column - remove leading zero for merges to work
            This part is now addressed when :attr:`Crosswalk.oge_xwalk` is made.
        3) make an eia composite key for grabbing EIA data

        """
        return (
            self.base_xwalk.assign(
                overall_comp_key=lambda x: np.where(
                    (x["plant_id_epa"].notnull()) & (x["plant_id_eia"].notnull()),
                    x["plant_id_epa"].astype(str)
                    + "_"
                    + x["plant_id_eia"].astype(str)
                    + "_"
                    + x["subplant_id"].astype(str),
                    pd.NA,
                )
            )
            .query("overall_comp_key.notnull()")
            .assign(
                overall_comp_key_eia=lambda x: np.where(
                    (x["plant_id_epa"].notnull()) & (x["plant_id_eia"].notnull()),
                    x["plant_id_eia"].astype(str) + "_" + x["subplant_id"].astype(str),
                    pd.NA,
                ),
            )
        )

    def reassign_fuel_group(
        self, xwalk: pd.DataFrame, when_below: float = 0.01
    ) -> pd.DataFrame:
        """Not sure this is a good idea...

        Args:
            xwalk:
            when_below:

        Returns:

        """
        df = (
            pd_read_pudl(
                "out_eia923__monthly_generation_fuel_combined",
                release=PUDL_RELEASE_VERSION,
            )
            .query(
                "energy_source_code in @UDAY_FOSSIL_FUEL_MAP "
                "& prime_mover_code in @FOSSIL_PRIME_MOVER_MAP"
            )
            .assign(
                fuel_group=lambda x: x.energy_source_code.replace(UDAY_FOSSIL_FUEL_MAP),
                prime_mover=lambda x: x.prime_mover_code.replace(
                    FOSSIL_PRIME_MOVER_MAP
                ),
            )
            .groupby(
                [
                    pd.Grouper(key="report_date", freq="YS"),
                    "plant_id_eia",
                    "prime_mover",
                    "fuel_group",
                ]
            )
            .net_generation_mwh.sum()
            .reset_index()
            .query("net_generation_mwh > 0")
            .assign(
                pp_share=lambda x: x.net_generation_mwh
                / x.groupby(
                    ["plant_id_eia", "prime_mover", "report_date"]
                ).net_generation_mwh.transform("sum"),
                fuel_count=lambda x: x.groupby(
                    ["plant_id_eia", "prime_mover", "report_date"]
                ).fuel_group.transform("count"),
                ppf=lambda x: x[
                    [
                        "plant_id_eia",
                        "prime_mover",
                        "fuel_group",
                    ]
                ]
                .astype(str)
                .agg("_".join, axis=1),
            )
        )
        all_time = (
            df.query("fuel_count > 1")
            .groupby(["plant_id_eia", "prime_mover", "fuel_group"])
            .pp_share.max()
        )
        return (
            xwalk.merge(
                all_time.reset_index(),
                on=["plant_id_eia", "prime_mover", "fuel_group"],
                how="left",
                validate="m:1",
            )
            .merge(
                all_time.reset_index()
                .groupby(["plant_id_eia", "prime_mover"])
                .agg({"fuel_group": "first", "pp_share": "max"})
                .rename(columns={"fuel_group": "fuel_group_max"})
                .fuel_group_max.reset_index(),
                on=["plant_id_eia", "prime_mover"],
                how="left",
                validate="m:1",
            )
            .assign(
                fuel_group_mod=lambda x: x.fuel_group.mask(
                    (x.pp_share < when_below) & x.pp_share.notna(), x.fuel_group_max
                )
            )
        )
