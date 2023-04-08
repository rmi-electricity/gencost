import pytest
from etoolbox.utils.testing import idfn

from gencost.waterfall import DataBySubplant, subplants_in_scenario_one


class TestDataBySubplant:
    def test_get_860_by_subplant(self, crosswalk, pudl_tabl):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df = dbp.get_860_by_x(merge_only=True, subplant_id_col="subplant_id")
        assert not df.empty

    @pytest.mark.parametrize("by_fuel", [True, False], ids=idfn)
    def test_get_bf923_by_subplant(self, crosswalk, pudl_tabl, by_fuel):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df = dbp.get_bf923_by_subplant(by_fuel=by_fuel)
        assert not df.empty

    def test_get_gen923_by_subplant(self, crosswalk, pudl_tabl):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df = dbp.get_gen923_by_subplant()
        assert not df.empty

    def test_get_gf923_by_subplant(self, crosswalk, pudl_tabl):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df_gen923 = dbp.get_gen923_by_subplant()
        df = dbp.get_gf923_by_subplant(subplants_in_scenario_one(df_gen923))
        assert not df.empty

    def test_get_cems_by_subplant(self, crosswalk, pudl_tabl):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df = dbp.get_cems_by_x(subplant_id_col="subplant_id")
        assert not df.empty

    def test_get_additional_generator_specs(self, crosswalk):
        """Perfunctory test."""
        dbs = DataBySubplant(crosswalk)
        df = dbs.get_additional_generator_specs_by_x(subplant_id_col="subplant_id")
        assert not df.empty

    def test_get_exa_by_subplant(self, crosswalk):
        """Perfunctory test."""
        dbs = DataBySubplant(crosswalk)
        df = dbs.get_exa_by_subplant()
        assert not df.empty


class TestDataByPrime:
    """Test aggregations by plant, prime, fuel."""

    def test_get_923_by_ppf(self, crosswalk, pudl_tabl):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df = dbp.get_gf923_by_prime(merge_only=True)
        assert not df.empty

    def test_get_cems_by_subplant(self, crosswalk, pudl_tabl):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df = dbp.get_cems_by_x(subplant_id_col="pf_subplant_id")
        assert not df.empty

    def test_get_860_by_prime(self, crosswalk, pudl_tabl):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df = dbp.get_860_by_x(merge_only=True, subplant_id_col="pf_subplant_id")
        assert not df.empty

    def test_get_additional_generator_specs_by_ppf(self, crosswalk):
        """Perfunctory test."""
        dbs = DataBySubplant(crosswalk)
        df = dbs.get_additional_generator_specs_by_x(subplant_id_col="pf_subplant_id")
        assert not df.empty

    def test_get_cost_data_by_ppf(self, crosswalk):
        """Perfunctory test."""
        dbs = DataBySubplant(crosswalk)
        df = dbs.get_cost_data_by_prime()
        assert not df.empty

    def test_get_exa_by_prime(self, crosswalk, pudl_tabl):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df = dbp.get_exa_by_prime()
        assert not df.empty


class TestFullWaterfall:
    def test_full_waterfall(self, crosswalk, pudl_tabl):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df = dbp.get_exa_all()
        assert not df.empty

    def test_merge_full(self, crosswalk, pudl_tabl):
        """Perfunctory test."""
        dbp = DataBySubplant(crosswalk)
        df = dbp.merge_all()
        assert not df.empty

    def test_compare_capacity_fig(self, crosswalk):
        go = pytest.importorskip("plotly.graph_objects")

        dbp = DataBySubplant(crosswalk)
        df = dbp.draw_capacity_ecdf(facet_row="year_group")
        assert isinstance(df, go.Figure)
