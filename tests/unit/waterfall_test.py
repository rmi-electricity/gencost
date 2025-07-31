import pytest
from etoolbox.utils.pudl import pd_read_pudl

from gencost.constants import PUDL_RELEASE_VERSION
from gencost.entity_ids import BA_REPLACE, add_ba_code


class TestFullWaterfall:
    def test_full_waterfall(self, databysubplant):
        """Perfunctory test."""
        df = databysubplant.get_exa_all()
        assert not df.empty

    def test_merge_full(self, databysubplant):
        """Perfunctory test."""
        df = databysubplant.merge_all()
        assert not df.empty

    def test_get_historical_by_generator(self, databysubplant):
        """Perfunctory test that the method produces something."""
        df = databysubplant.get_historical_by_generator()
        assert not df.empty

    def test_fill_in_eternals(self, databysubplant):
        """Perfunctory test that the method produces something."""
        df = databysubplant.fill_in_ep_data()
        assert not df.empty

    def test_get_eternally_present_by_generator(self, databysubplant):
        """Perfunctory test that the method produces something."""
        df = databysubplant.get_eternally_present_by_generator()
        assert not df.empty

    def test_compare_capacity_fig(self, databysubplant):
        go = pytest.importorskip("plotly.graph_objects")

        df = databysubplant.draw_capacity_ecdf(facet_row="year_group")
        assert isinstance(df, go.Figure)


class TestEntityID:
    def test_add_ba_code(self):
        """Test that we can add BA codes."""
        gens = (
            pd_read_pudl(
                "core_eia860m__changelog_generators", release=PUDL_RELEASE_VERSION
            )
            .groupby(["plant_id_eia", "generator_id"], as_index=False)
            .last()
        )
        df = add_ba_code(gens)
        assert df.final_ba_code.notna().shape == df.final_ba_code.shape

    def test_add_ba_code_rollup(self):
        """Test that we can rollup EIA BAs."""
        gens = (
            pd_read_pudl(
                "core_eia860m__changelog_generators", release=PUDL_RELEASE_VERSION
            )
            .groupby(["plant_id_eia", "generator_id"], as_index=False)
            .last()
        )
        df = add_ba_code(gens, ba_rollup_only=True)
        assert (
            df.balancing_authority_code_eia.notna().shape
            == df.final_ba_code.notna().shape
        )
        assert all(x not in BA_REPLACE for x in df.final_ba_code.unique())
