#!/usr/bin/env python
"""\
Join the linear model coefficients to the observed values in the DataBySubplant dataset;
use Polars in lieu of R because this data fans out with the joins, and Polars might be
optimal for this memory usage.
"""

__author__ = "Andrew Bartnof for RMI"
__email__ = "abartnof.contractor@rmi.org"
__date__ = "July, 2023"

import os

# Load packages
import polars as pl

os.chdir(
    "/Users/andrewbartnof/Documents/rmi/gencost/exploration_of_power_plant_characteristics"
)

# Load and transform datasets simultaneously, to make use of Polars' optimisations.
#
# Collect three observed variables that will be necessary for final calculations
ExtraVariables = (
    pl.scan_parquet("input_data/data_by_subplant.parquet")
    .with_row_count(name="rowid", offset=1)  # R starts at 1
    .select(["rowid", "capacity_mw", "gross_generation_mwh", "generator_starts"])
    .with_columns(pl.col("rowid").cast(pl.Int64))
    .collect()
)

# Table that assigns each rowid to a cluster
Cls = pl.read_csv("clean_data/clustered_data_by_subplant.csv")

# Table that shows the RMSE for each formula, for each cluster; these are ranked in terms of their  # noqa: E501, W505
# goodness-of-fit, which means that if we limit to the top n best-fitting models, and then semi-join  # noqa: E501, W505
# this table into the AllPossibleCoef table, we can drastically limit how large our joins will get.  # noqa: E501, W505
MeanRmse = (
    pl.scan_csv("clean_data/mean_rmse.csv")
    .filter(pl.col("rank") == 1)  # <- THIS IS WHAT LIMITS OUTPUT SIZE
    .select(["prime_mover", "cls", "formula"])
    .collect()
)

# Collect the coefficients previously extracted from fitted models for each possible formula.  # noqa: E501, W505
AllPossibleCoef = (  # Semijoin with MeanRmse, in order to only include the most useful formulas  # noqa: E501
    pl.read_csv("clean_data/all_possible_coefficients.csv")
    .select(["prime_mover", "cls", "formula", "variable", "category", "coefficient"])
    .join(MeanRmse, on=["prime_mover", "cls", "formula"], how="semi")
)

# Cluster the dataset, apply the top n best-fitting formulas' coefficients, multiply the coefficients  # noqa: E501, W505
# by their values, and sum up these values by their category (fixed cost, variable, or starts) in order  # noqa: E501, W505
# to ultimately create human-readable metrics; fom, vom, som, and om_per_mwh
Results = (
    pl.scan_csv(
        "clean_data/cleaned_data_by_subplant_data.csv", infer_schema_length=10000
    )
    .melt(id_vars=["rowid", "prime_mover"])
    .collect()
    .join(Cls, on="rowid", how="inner")  # Add cluster info
    .join(AllPossibleCoef, on=["prime_mover", "cls", "variable"])
    .with_columns(
        (pl.col("value") * pl.col("coefficient")).alias("value_x_coefficient")
    )
    .groupby(["rowid", "prime_mover", "cls", "formula", "category"])
    .agg(pl.col("value_x_coefficient").sum().alias("summed_value_x_coefficient"))
    .pivot(
        values="summed_value_x_coefficient",
        index=["rowid", "prime_mover", "cls", "formula"],
        columns="category",
        aggregate_function="first",
    )
    .join(ExtraVariables, on="rowid", how="inner")
    .with_columns(
        (pl.col("fixed") / (pl.col("capacity_mw") * 1000)).alias(
            "fom"
        ),  # fom = fixed / (capacity_mw * 1000),
        (pl.col("variable") / pl.col("gross_generation_mwh")).alias(
            "vom"
        ),  # vom = variable / gross_generation_mwh,
        (
            pl.col("start")
            / (pl.col("capacity_mw") * pl.col("generator_starts") * 1000)
        ).alias("som"),  # som = start / (capacity_mw * generator_starts * 1000),
    )
    .with_columns(
        (
            pl.col("vom")
            + (
                pl.col("som")
                * pl.col("capacity_mw")
                * pl.col("generator_starts")
                * 1000
            )
            + (pl.col("fom") * pl.col("capacity_mw") * 1000)
            / pl.col("gross_generation_mwh")
        ).alias(
            "om_per_mwh"
        )  # (som * capacity_mw * generator_starts * 1000 + fom * capacity_mw * 1000) / gross_generation_mwh) + vom  # noqa: E501
    )
    .select(
        ["rowid", "prime_mover", "cls", "formula", "fom", "vom", "som", "om_per_mwh"]
    )
)

# Write results and close out script
fn = "clean_data/vom_fom_som.csv"
Results.write_csv(file=fn)
quit()
