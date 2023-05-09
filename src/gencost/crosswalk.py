import logging
import warnings

import networkx as nx
import numpy as np
import pandas as pd
from etoolbox.utils.pudl import make_pudl_tabl
from platformdirs import user_cache_path

from gencost.constants import (
    FOSSIL_PRIME_MOVER_MAP,
    FUEL_GROUP_MAP,
    UDAY_FOSSIL_FUEL_MAP,
)
from gencost.data_setup import main as data_setup
from gencost.package_data import PACKAGE_PATH

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


# from oge.data_cleaning
def generate_subplant_ids(pudl_tabl, cems_ids):
    """
    Groups units and generators into unique subplant groups.

    This function consists of three primary parts:
    1. Identify a list of all unique plant-units that exist in the CEMS data
        for the years in question. This will be used to filter the crosswalk.
    2. Load the EPA-EIA crosswalk and filter it based on the units that exist
        in the CEMS data for the years in question
    3. Use graph analysis to identify distinct groupings of EPA units and EIA
        generators based on 1:1, 1:m, m:1, or m:m relationships.

    Returns:
        exports the subplant crosswalk to a csv file
        cems_ids and gen_fuel_allocated with subplant_id added
    """

    # load the crosswalk and filter it by the data that actually exists in cems
    # filter the crosswalk to drop any units that don't exist in CEMS
    filtered_crosswalk = filter_crosswalk(pudl_tabl.epacamd_eia(), cems_ids)

    # use graph analysis to identify subplants
    crosswalk_with_subplant_ids = make_subplant_ids(
        filtered_crosswalk,
        source_keys=["plant_id_eia", "emissions_unit_id_epa"],
        source_name="combustor_id",
        target_keys=["plant_id_eia", "generator_id"],
        target_name="generator_id_unique",
        new_key_name="subplant_id",
    )

    # change the eia plant id to int
    crosswalk_with_subplant_ids["plant_id_eia"] = crosswalk_with_subplant_ids[
        "plant_id_eia"
    ].astype(int)

    # change the order of the columns
    crosswalk_with_subplant_ids = crosswalk_with_subplant_ids[
        [
            "plant_id_epa",
            "emissions_unit_id_epa",
            "plant_id_eia",
            "generator_id",
            "subplant_id",
        ]
    ]

    # update the subplant_crosswalk to ensure completeness
    # prepare the subplant crosswalk by adding a complete list of generators and
    # adding the unit_id_pudl column
    complete_generator_ids = (
        pudl_tabl.gens_eia860()[["plant_id_eia", "generator_id", "unit_id_pudl"]]
        .sort_values(["plant_id_eia", "generator_id", "unit_id_pudl"])
        .drop_duplicates(subset=["plant_id_eia", "generator_id"])
    )
    # RMI: 2708 missing unit_id_pudl for 2A and 2B because they retired long ago,
    # or something
    complete_generator_ids.loc[
        (complete_generator_ids["plant_id_eia"] == 2708)
        & (complete_generator_ids["generator_id"].isin(["1A", "1B", "2A", "2B"])),
        "unit_id_pudl",
    ] = 3

    subplant_crosswalk_complete = crosswalk_with_subplant_ids.merge(
        complete_generator_ids,
        how="outer",
        on=["plant_id_eia", "generator_id"],
        validate="m:1",
    )
    # also add a complete list of cems emissions_unit_id_epa
    subplant_crosswalk_complete = subplant_crosswalk_complete.merge(
        cems_ids[["plant_id_eia", "emissions_unit_id_epa"]]
        .drop_duplicates()
        .astype({"plant_id_eia": "Int64"}),
        how="outer",
        on=["plant_id_eia", "emissions_unit_id_epa"],
        validate="m:1",
    )
    # update the subplant ids for each plant
    subplant_crosswalk_complete = subplant_crosswalk_complete.groupby(
        "plant_id_eia"
    ).apply(update_subplant_ids)

    # remove the intermediate columns created by update_subplant_ids
    subplant_crosswalk_complete["subplant_id"].update(
        subplant_crosswalk_complete["new_subplant"]
    )
    subplant_crosswalk_complete = subplant_crosswalk_complete.reset_index(drop=True)[
        [
            "plant_id_epa",
            "emissions_unit_id_epa",
            "plant_id_eia",
            "generator_id",
            "subplant_id",
            "unit_id_pudl",
        ]
    ]

    # inlining oge.data_cleaning.manually_update_subplant_id
    # This is temporary until the pudl subplant crosswalk includes boiler-generator
    # id matches.
    subplant_crosswalk_complete.loc[
        subplant_crosswalk_complete["plant_id_eia"] == 1391, "subplant_id"
    ] = 0

    subplant_crosswalk_complete = subplant_crosswalk_complete.drop_duplicates(
        subset=[
            "plant_id_epa",
            "emissions_unit_id_epa",
            "plant_id_eia",
            "generator_id",
            "subplant_id",
        ],
        keep="last",
    )

    # # add proposed operating dates and retirements to the subplant id crosswalk
    # subplant_crosswalk_complete = add_operating_and_retirement_dates(
    #     subplant_crosswalk_complete, pudl_tabl
    # )
    return subplant_crosswalk_complete.astype(
        {
            "plant_id_epa": "Int64",
            "emissions_unit_id_epa": "string",
            "plant_id_eia": "Int64",
            "generator_id": "string",
            "subplant_id": "Int64",
            "unit_id_pudl": "Int64",
            # "current_planned_generator_operating_date": "datetime64",
            # "generator_retirement_date": "datetime64",
        }
    )


# from oge.data_cleaning
def update_subplant_ids(subplant_crosswalk):
    """Ensures a complete and accurate subplant_id mapping for all generators.

    Args:
        subplant_crosswalk: a dataframe containing the output of
            `epacamd_eia_crosswalk.make_subplant_ids` with

    NOTE:
        1. This function is a temporary placeholder until the
            `pudl.analysis.epacamd_eia_crosswalk` code is updated.
        2. This function is meant to be applied using a .groupby("plant_id_eia").apply()
            function. This function
        will only properly work when applied to a single plant_id_eia at a time.

    Data Preparation
        Because the existing subplant_id crosswalk was only meant to map CAMD units
        to EIA generators, it is missing a large number of subplant_ids for generators
        that do not report to CEMS. Before applying this function to the subplant
        crosswalk, the crosswalk must be completed with all generators by outer
        merging in the complete list of generators from EIA-860 (specifically the
        gens_eia860 table from pudl). This dataframe also contains the complete list
        of `unit_id_pudl` mappings that will be necessary.

    High-level overview of method:
        1. Use the PUDL subplant_id if available. In the case where a unit_id_pudl
            groups several subplants, we overwrite these multiple existing subplant_id
            with a single subplant_id.
        2. Where there is no PUDL subplant_id, we use the unit_id_pudl to assign a
            unique subplant_id
        3. Where there is neither a pudl subplant_id nor unit_id_pudl, we use the
            generator ID to assign a unique subplant_id
        4. All of the new unique ids are renumbered in consecutive ascending order


    Detailed explanation of steps:
        1. Because the current subplant_id code does not take boiler-generator
            associations into account, there may be instances where the code assigns
            generators to different subplants when in fact, according to the
            boiler-generator association table, these generators are grouped into a
            single unit based on their boiler associations. The first step of this
            function is thus to identify if multiple subplant_id have been assigned to
            a single unit_id_pudl. If so, we replace the existing subplant_ids with a
            single subplant_id. For example, if a generator A was assigned subplant_id
            0 and generator B was assigned subplant_id 1, but both generators A and B
            are part of unit_id_pudl 1, we would re-assign the subplant_id to both
            generators to 0 (we always use the lowest number subplant_id in each
            unit_id_pudl group). This may result in some subplant_id being skipped,
            but this is okay because we will later renumber all subplant ids (i.e. if
            there were also a generator C with subplant_id 2, there would no be no
            subplant_id 1 at the plant) Likewise, sometimes multiple unit_id_pudl are
            connected to a single subplant_id, so we also correct the unit_id_pudl
            based on these connections.
        2. The second issue is that there are many NA subplant_id that we should fill.
            To do this, we first look at unit_id_pudl. If a group of generators are
            assigned a unit_id_pudl but have NA subplant_ids, we assign a single
            new subplant_id to this group of generators. If there are still generators
            at a plant that have both NA subplant_id and NA unit_id_pudl, we for now
            assume that each of these generators consitutes its own subplant. We thus
            assign a unique subplant_id to each generator that is unique from any
            existing subplant_id already at the plant. In the case that there are
            multiple emissions_unit_id_epa at a plant that are not matched to any
            other identifiers (generator_id, unit_id_pudl, or subplant_id), as is the
            case when there are units that report to CEMS but which do not exist in
            the EIA data, we assign these units to a single subplant.


    """
    # Step 1: Create corrected versions of subplant_id and unit_id_pudl
    # if multiple unit_id_pudl are connected by a single subplant_id,
    # unit_id_pudl_connected groups these unit_id_pudl together
    subplant_crosswalk = connect_ids(
        subplant_crosswalk, id_to_update="unit_id_pudl", connecting_id="subplant_id"
    )
    # if multiple subplant_id are connected by a single unit_id_pudl, group these
    # subplant_id together
    subplant_crosswalk = connect_ids(
        subplant_crosswalk, id_to_update="subplant_id", connecting_id="unit_id_pudl"
    )

    # Step 2: Fill missing subplant_id
    # We will use unit_id_pudl to fill missing subplant ids, so first we need to fill
    # any missing unit_id_pudl
    # We do this by assigning a new unit_id_pudl to each generator that isn't already
    # grouped into a unit

    # create a numeric version of each generator_id
    # ngroup() creates a unique number for each element in the group
    subplant_crosswalk["numeric_generator_id"] = subplant_crosswalk.groupby(
        ["plant_id_eia", "generator_id"], dropna=False
    ).ngroup()
    # when filling in missing unit_id_pudl, we don't want these numeric_generator_id
    # to overlap existing unit_id to ensure this, we will add 1000 to each of these
    # numeric generator ids to ensure they are unique 1000 was chosen as an
    # arbitrarily high number, since the largest unit_id_pudl is ~ 10.
    subplant_crosswalk["numeric_generator_id"] = (
        subplant_crosswalk["numeric_generator_id"] + 1000
    )
    # fill any missing unit_id_pudl with a number for each unique generator
    subplant_crosswalk["unit_id_pudl_filled"] = (
        subplant_crosswalk["unit_id_pudl_connected"]
        .fillna(subplant_crosswalk["subplant_id_connected"] + 100)
        .fillna(subplant_crosswalk["numeric_generator_id"])
    )
    # create a new unique subplant_id based on the connected subplant ids and the
    # filled unit_id
    subplant_crosswalk["new_subplant"] = subplant_crosswalk.groupby(
        ["plant_id_eia", "subplant_id_connected", "unit_id_pudl_filled"],
        dropna=False,
    ).ngroup()

    return subplant_crosswalk


# from oge.data_cleaning
def connect_ids(df, id_to_update, connecting_id):
    """Corrects an id value if it is connected by an id value in another column.

    if multiple subplant_id are connected by a single unit_id_pudl, this groups
        these subplant_id together
    if multiple unit_id_pudl are connected by a single subplant_id, this groups
        these unit_id_pudl together

    Args:
        df: dataframe containing columns with id_to_update and connecting_id columns
            subplant_unit_pairs
    """

    # get a table with all unique subplant to unit pairs
    subplant_unit_pairs = df[
        ["plant_id_eia", "subplant_id", "unit_id_pudl"]
    ].drop_duplicates()

    # identify if any non-NA id_to_update are duplicated, indicated that it is
    # associated with multiple connecting_id
    duplicates = subplant_unit_pairs[
        (subplant_unit_pairs.duplicated(subset=id_to_update, keep=False))
        & (~subplant_unit_pairs[id_to_update].isna())
    ].copy()

    # if there are any duplicate units, indicating an incorrect id_to_update, fix the
    # id_to_update
    df[f"{connecting_id}_connected"] = df[connecting_id]
    if len(duplicates) > 0:
        # find the lowest number subplant id associated with each duplicated
        # unit_id_pudl
        duplicates.loc[:, f"{connecting_id}_to_replace"] = (
            duplicates.groupby(["plant_id_eia", id_to_update])[connecting_id]
            .min()
            .iloc[0]
        )
        # merge this replacement subplant_id into the dataframe and use it to update
        # the existing subplant id
        df = df.merge(
            duplicates,
            how="left",
            on=["plant_id_eia", id_to_update, connecting_id],
            validate="m:1",
        )
        df[f"{connecting_id}_connected"].update(df[f"{connecting_id}_to_replace"])
    return df


# from oge.data_cleaning
def add_operating_and_retirement_dates(df, pudl_tabl):
    """Adds columns listing a generator's planned operating date or retirement date
    to a dataframe."""
    generator_status = pudl_tabl.gens_eia860().loc[
        :,
        [
            "plant_id_eia",
            "generator_id",
            "report_date",
            "operational_status",
            "current_planned_generator_operating_date",
            "generator_retirement_date",
        ],
    ]
    # only keep values that have a planned operating date or retirement date
    generator_status = generator_status[
        (~generator_status["current_planned_generator_operating_date"].isna())
        | (~generator_status["generator_retirement_date"].isna())
    ]
    # drop any duplicate entries
    generator_status = generator_status.sort_values(
        by=["plant_id_eia", "generator_id", "report_date"]
    ).drop_duplicates(
        subset=[
            "plant_id_eia",
            "generator_id",
            "current_planned_generator_operating_date",
            "generator_retirement_date",
        ],
        keep="last",
    )
    # for any generators that have different retirement or planned dates reported
    # in different years, keep the most recent value
    generator_status = generator_status.sort_values(
        by=["plant_id_eia", "generator_id", "report_date"]
    ).drop_duplicates(subset=["plant_id_eia", "generator_id"], keep="last")

    # merge the dates into the crosswalk
    df = df.merge(
        generator_status[
            [
                "plant_id_eia",
                "generator_id",
                "current_planned_generator_operating_date",
                "generator_retirement_date",
            ]
        ],
        how="left",
        on=["plant_id_eia", "generator_id"],
        validate="m:1",
    )

    return df


# from pudl.transform.epacems
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


def pudl_xwalk(pudl_tabl):
    cems_ids = harmonize_eia_epa_orispl(
        pd.read_parquet(PACKAGE_PATH / "camd_unit_starts_ms.parquet.gzip").rename(
            columns={
                "plant_id_cems": "plant_id_epa",
                "unit_id_cems": "emissions_unit_id_epa",
                "gross_gen": "gross_generation_mwh",
                "gross_gen_max": "camd_capacity_mw",
                "gen_starts": "generator_starts",
            }
        ),
        pudl_tabl.epacamd_eia(),
    )

    filtered_crosswalk = filter_crosswalk(pudl_tabl.epacamd_eia(), cems_ids)

    # use graph analysis to identify subplants
    return make_subplant_ids(
        filtered_crosswalk,
        source_keys=["plant_id_eia", "emissions_unit_id_epa"],
        source_name="combustor_id",
        target_keys=["plant_id_eia", "generator_id"],
        target_name="generator_id_unique",
        new_key_name="subplant_id",
    )[
        [
            "plant_id_epa",
            "emissions_unit_id_epa",
            "plant_id_eia",
            "generator_id",
            "subplant_id",
            "boiler_id",
        ]
    ]


class Crosswalk:
    def __init__(self, pudl_tabl=None, clobber=False):
        if pudl_tabl is None:
            data_setup()
            self.pudl_tabl = make_pudl_tabl(
                user_cache_path("gencost", "rmi") / "pdltbl",
                tables=(
                    "boil_eia860",
                    "gf_eia923",
                    "gen_original_eia923",
                    "bf_eia923",
                    "gens_eia860",
                    "plants_eia860",
                    "epacamd_eia",
                    "own_eia860",
                    "bga_eia860",
                    "utils_eia860",
                    "frc_eia923",
                ),
            )
        else:
            self.pudl_tabl = pudl_tabl
        file = user_cache_path("gencost", "rmi") / "xwalk_pudl.parquet"
        if not file.exists() or clobber:
            if not file.parent.exists():
                file.parent.mkdir(parents=True)
            df = self.pudl_tabl.epacamd_eia_subplant_ids()
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
                if (
                    isinstance(replacement, pd.Series)
                    and len(replacement.unique()) == 1
                ):
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

            df.to_parquet(file)
            self.base_xwalk = df
        else:
            self.base_xwalk = pd.read_parquet(file)

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
            self.pudl_tabl.gens_eia860()
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
            self.pudl_tabl.gf_eia923()
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
