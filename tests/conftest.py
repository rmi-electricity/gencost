"""PyTest configuration module. Defines useful fixtures, command line args."""
import logging
from pathlib import Path

import pytest
from etoolbox.utils.pudl import make_pudl_tabl
from platformdirs import user_cache_path

logger = logging.getLogger(__name__)


def pytest_addoption(parser: pytest.Parser) -> None:
    """Add package-specific command line options to pytest.

    This is slightly magical -- pytest has a hook that will run this function
    automatically, adding any options defined here to the internal pytest options that
    already exist.
    """
    parser.addoption(
        "--sandbox",
        action="store_true",
        default=False,
        help="Flag to indicate that the tests should use a sandbox.",
    )


@pytest.fixture(scope="session")
def test_dir() -> Path:
    """Return the path to the top-level directory containing the tests.

    This might be useful if there's test data stored under the tests directory that
    you need to be able to access from elsewhere within the tests.

    Mostly this is meant as an example of a fixture.
    """
    return Path(__file__).parent


@pytest.fixture(scope="session")
def pudl_tabl():
    return make_pudl_tabl(
        user_cache_path("gencost", "rmi") / "pdltbl",
        tables=(
            "boil_eia860",
            "gf_eia923",
            "gen_original_eia923",
            "bf_eia923",
            "gens_eia860",
            "plants_eia860",
            "epacamd_eia",
            "own_eia860",
            "bga_eia860",
            "utils_eia860",
            "frc_eia923",
        ),
    )


@pytest.fixture(
    scope="session",
    # params=[
    #     "pudl",
    #     "oge",
    # ],
)
def crosswalk(
    pudl_tabl,
    # request
):
    from gencost.crosswalk import Crosswalk

    return Crosswalk(
        pudl_tabl,
        # xwalk_source=request.param
    )
