"""
scenarios to explore:
    real parasitic_load < 0
    real parasitic_load > 1
    fitted parasitic_load < 0
    fitted_parasitic_load > 1
"""

import pandas as pd
from predict_parasitic_load import predict_parasitic_load

DataBySubplant = pd.read_parquet("subplant_w_tech_by_capacity.parquet")
Modeled = predict_parasitic_load(DataBySubplant, DataBySubplant)
Modeled.to_csv("modeled.csv")
