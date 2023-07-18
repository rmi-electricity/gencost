import polars as pl
import os
os.chdir('/Users/andrewbartnof/Documents/rmi/gencost/exploration_of_power_plant_characteristics')

ExtraVariables = (
    pl.scan_parquet('input_data/data_by_subplant.parquet')
    .with_row_count(name='rowid', offset=1) # R starts at 1
        #infer_schema_length=10000)
    .select(['rowid', 'capacity_mw', 'gross_generation_mwh', 'generator_starts'])
    .with_columns(
        pl.col('rowid').cast(pl.Int64)
        )
    .collect()
)

Cls = pl.read_csv('clean_data/clustered_data_by_subplant.csv')

MeanRmse = (
        pl.scan_csv('clean_data/mean_rmse.csv')
        .filter(pl.col('rank') <= 100)  # <- THIS IS WHAT LIMITS OUTPUT SIZE
        .select(['prime_mover', 'cls', 'formula'])
        .collect()
)

AllPossibleCoef = ( # Semijoin with MeanRmse, in order to only include the most useful formulas
        pl.read_csv('clean_data/all_possible_coefficients.csv') 
        .select(['prime_mover', 'cls', 'formula', 'variable', 'category', 'coefficient'])
        .join(MeanRmse, on=['prime_mover', 'cls', 'formula'], how='semi')
        )

Results = (
    pl.scan_csv('clean_data/cleaned_data_by_subplant_data.csv', 
        infer_schema_length=10000)
    .melt(id_vars=['rowid', 'prime_mover'])
    .collect()
    .join(Cls, on='rowid', how='inner') # Add cluster info
    .join(AllPossibleCoef, on=['prime_mover', 'cls', 'variable'])
    .with_columns(
        (pl.col('value') * pl.col('coefficient')).alias('value_x_coefficient')
    )
    .groupby(['rowid', 'prime_mover', 'cls', 'formula', 'category'])
        .agg(
            pl.col('value_x_coefficient').sum().alias('summed_value_x_coefficient')
        )
    .pivot(
        values='summed_value_x_coefficient', 
        index=['rowid', 'prime_mover','cls','formula'], 
        columns='category',
        aggregate_function='first'
    ).join(ExtraVariables, on='rowid', how='inner')
    .with_columns(
        ( pl.col('fixed') / (pl.col('capacity_mw') * 1000) ).alias('fom'), # fom = fixed / (capacity_mw * 1000),
        ( pl.col('variable') / pl.col('gross_generation_mwh') ).alias('vom'), # vom = variable / gross_generation_mwh,
        ( pl.col('start') / (pl.col('capacity_mw') * pl.col('generator_starts') * 1000) ).alias('som'), #som = start / (capacity_mw * generator_starts * 1000),
    ).with_columns(
        ( 
            pl.col('vom') +
            ( pl.col('som') * pl.col('capacity_mw') * pl.col('generator_starts') * 1000 ) +
            ( pl.col('fom') * pl.col('capacity_mw') * 1000 ) / pl.col('gross_generation_mwh')
        ).alias('om_per_mwh') #(som * capacity_mw * generator_starts * 1000 + fom * capacity_mw * 1000) / gross_generation_mwh) + vom
    )
)

fn = 'clean_data/vom_fom_som.csv'
Results.write_csv(file=fn)

quit()
