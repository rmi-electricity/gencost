import pandas as pd

from gencost.atb import get_atb


def test_get_atb():
    """Perfunctory test of atb functionality."""
    out = get_atb(
        pd.DataFrame(
            {
                "plant_id_eia": [1],
                "generator_id": ["1"],
                "operating_date": pd.to_datetime(2026, format="%Y"),
                "technology_description": ["Natural Gas Fired Combined Cycle"],
                "final_ba_code": ["FPC"],
            }
        )
    )
    assert not out.empty
