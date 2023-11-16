# flake8: noqa
import os

import pandas as pd

# can use tot_capacity for capacity_mw if need be

remove_chars = r"$?={}\x02\x00"

os.chdir("/Users/andrewbartnof/Documents/rmi/gencost/name_matching")

Data = pd.read_excel("input_data/rmi.xlsx")
Data = Data[
    ["plant_name", "Plant", "report_year", "tot_capacity", "Technology 1", "plant_kind"]
]

Data["plant_name"] = Data["plant_name"].astype(pd.StringDtype())
Data["plant_name"] = Data["plant_name"].str.normalize("NFKD")
Data["plant_name"] = Data["plant_name"].str.encode("ascii", errors="ignore")
Data["plant_name"] = Data["plant_name"].str.decode("ascii", errors="ignore")
Data["plant_name"] = Data["plant_name"].str.lower()
Data["plant_name"] = Data["plant_name"].str.replace(
    r"[" + remove_chars + r"]+", "", regex=True
)
Data["plant_name"] = Data["plant_name"].str.replace(r"\s+", " ", regex=True)
Data["plant_name"] = Data["plant_name"].str.strip()

Data.rename(
    columns={"plant_name": "plant_name_ferc", "Plant": "plant_id_eia"}, inplace=True
)

# Data.rename(columns={'plant_name': 'plant_name_ferc', 'Plant': 'plant_id_eia', 'Best Match Plant Prime': 'plant_name_eia'}, inplace=True)

Data["plant_id_eia"] = (
    Data["plant_id_eia"].astype("Int64", errors="ignore").astype("str")
)

Data.to_csv("clean_data/rmi.csv", index=False)
