import pandas as pd
import os
os.chdir('/Users/andrewbartnof/Documents/rmi/gencost/exploration_of_power_plant_characteristics')

Clusters = pd.read_csv('clean_data/clustered_data_by_subplant.csv')
CleanedDataBySubplant = pd.read_csv('clean_data/cleaned_data_by_subplant_data.csv')
AllPossibleCoefficients = pd.read_csv('clean_data/all_possible_coefficients.csv')

variables_to_select = ['rowid', 'prime_mover'] + AllPossibleCoefficients['variable'].unique().tolist() 
ClusteredDataBySubplant = pd.merge(
        left=Clusters, 
        right=CleanedDataBySubplant[variables_to_select], 
        how='inner', 
        on='rowid'
        )
ClusteredValuesLong = pd.melt(
        ClusteredDataBySubplant, 
        id_vars=['rowid', 'prime_mover', 'cls'], 
        value_vars= AllPossibleCoefficients['variable'].unique().tolist()
        )
# This step consumes too much memory, just like in R
ValuesAndCoefficients = pd.merge(
        left=ClusteredValuesLong,
        right=AllPossibleCoefficients,
        how='inner',
        on=['prime_mover', 'cls']
        )
