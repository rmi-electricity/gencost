import pandas as pd
import pytest
from etoolbox.utils.testing import idfn


class TestCrosswalk:
    """Test the Crosswalk."""

    @pytest.mark.parametrize("attr", ["grand_crosswalk", "safe_xwalk"], ids=idfn)
    def test_ppf_crosswalk_unique(self, crosswalk, attr):
        """Test that there is a single unique pf_subplant_id for each
        (plant_id_eia, prime_mover, fuel_group)."""
        df = getattr(crosswalk, attr).copy()
        q = (
            df.groupby(["plant_id_eia", "prime_mover", "fuel_group"])
            .agg({"pf_subplant_id": pd.Series.nunique})
            .query("pf_subplant_id > 1")
        )
        assert q.empty, f"{q.query('pf_subplant_id > 1').squeeze().to_dict()}"

    @pytest.mark.parametrize("attr", ["grand_crosswalk", "safe_xwalk"], ids=idfn)
    def test_ppf_camd_unit_crosswalk_unique(self, crosswalk, attr):
        """Test that there is a single unique pf_subplant_id for each
        (plant_id_eia, emissions_unit_id_epa)."""
        df = getattr(crosswalk, attr).copy()
        q = (
            df.groupby(["plant_id_eia", "emissions_unit_id_epa"])
            .agg({"pf_subplant_id": pd.Series.nunique})
            .query("pf_subplant_id > 1")
        )
        assert q.empty, f"{q.query('pf_subplant_id > 1').squeeze().to_dict()}"

    @pytest.mark.parametrize(
        "attr", ["base_xwalk", "grand_crosswalk", "safe_xwalk"], ids=idfn
    )
    def test_gen_crosswalk_unique(self, crosswalk, attr):
        """Test that there is a single unique subplant_id for each
        (plant_id_eia, generator_id)."""
        df = getattr(crosswalk, attr).copy()
        q = df.groupby(["plant_id_eia", "generator_id"]).agg(
            {"subplant_id": pd.Series.nunique}
        )
        q = q[q.subplant_id > 1]
        assert q.empty, f"{q.query('subplant_id > 1').squeeze().to_dict()}"

    @pytest.mark.parametrize(
        "attr", ["base_xwalk", "grand_crosswalk", "safe_xwalk"], ids=idfn
    )
    def test_eia_unit_crosswalk_unique(self, crosswalk, attr):
        """Test that there is a single unique subplant_id for each
        (plant_id_eia, emissions_unit_id_epa)."""
        df = getattr(crosswalk, attr).copy()
        q = df.groupby(["plant_id_eia", "emissions_unit_id_epa"]).agg(
            {"subplant_id": pd.Series.nunique}
        )
        q = q[q.subplant_id > 1]
        assert q.empty, f"{q.query('subplant_id > 1').squeeze().to_dict()}"

    @pytest.mark.parametrize(
        "attr", ["base_xwalk", "grand_crosswalk", "safe_xwalk"], ids=idfn
    )
    def test_epa_unit_crosswalk_unique(self, crosswalk, attr):
        """Test that there is a single unique subplant_id for each
        (plant_id_eia, emissions_unit_id_epa)."""
        df = getattr(crosswalk, attr).copy()
        q = df.groupby(["plant_id_epa", "emissions_unit_id_epa"]).agg(
            {"subplant_id": pd.Series.nunique}
        )
        q = q[q.subplant_id > 1]
        assert q.empty, f"{q.query('subplant_id > 1').squeeze().to_dict()}"

    @pytest.mark.parametrize(
        "attr",
        [pytest.param("grand_crosswalk", marks=pytest.mark.xfail), "safe_xwalk"],
        ids=idfn,
    )
    def test_crosswalk_unique_pf_prime(self, crosswalk, attr):
        """Test that there is a single unique prime_mover for each
        (plant_id_eia, pf_subplant_id)."""
        df = getattr(crosswalk, attr).copy()
        q = (
            df.groupby(["plant_id_eia", "pf_subplant_id"])
            .agg({"prime_mover": pd.Series.nunique})
            .query("prime_mover > 1")
        )
        assert (
            q.empty
        ), f"pf_subplant multi prime{q.query('prime_mover > 1').squeeze().to_dict()}"

    @pytest.mark.parametrize(
        "attr",
        [pytest.param("grand_crosswalk", marks=pytest.mark.xfail), "safe_xwalk"],
        ids=idfn,
    )
    def test_crosswalk_unique_prime(self, crosswalk, attr):
        """Test that there is a single unique prime_mover for each
        (plant_id_eia, subplant_id)."""
        df = getattr(crosswalk, attr).copy()
        q = (
            df.groupby(["plant_id_eia", "subplant_id"])
            .agg({"prime_mover": pd.Series.nunique})
            .query("prime_mover > 1")
        )
        assert (
            q.empty
        ), f"subplant multi prime {q.query('prime_mover > 1').squeeze().to_dict()}"

    def test_make_comp_key(self, crosswalk):
        """Test that make_comp_key works properly."""
        df = crosswalk.make_comp_key().copy()
        assert not df.empty

    @pytest.mark.skip
    def test_fuel_weights(self, crosswalk):
        df = crosswalk.reassign_fuel_group()
        assert not df.empty
