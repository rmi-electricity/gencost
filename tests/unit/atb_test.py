import pandas as pd

from gencost.atb import get_atb


def test_get_atb():
    """Perfunctory test of atb functionality."""
    out = get_atb(
        pd.DataFrame(
            {
                "plant_id_eia": list(range(6)),
                "generator_id": ["1"] * 6,
                "operating_date": pd.to_datetime(
                    [2026, 2030, 2030, 2022, 2025, 2018], format="%Y"
                ),
                "technology_description": [
                    "Natural Gas Fired Combined Cycle",
                    "Solar Photovoltaic",
                    "Solar Photovoltaic",
                    "Nuclear",
                    "Offshore Wind Turbine",
                    "Onshore Wind Turbine",
                ],
                "final_ba_code": ["FPC"] * 6,
            }
        ).set_index(["plant_id_eia", "generator_id"])
    )
    assert not out.empty
