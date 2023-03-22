"""Load or create PUDL objects."""
import logging

import sqlalchemy as sa
from etoolbox.datazip import DataZip
from platformdirs import user_cache_path
from pudl.output.pudltabl import PudlTabl
from pudl.workspace.setup import get_defaults

LOGGER = logging.getLogger(__name__)


def get_pudl_tabl(
    clobber=False,
    tables=(
        "gf_eia923",
        "gen_original_eia923",
        "bf_eia923",
        "gens_eia860",
        "plants_eia860",
        "epacamd_eia",
    ),
    cache_path=user_cache_path("gencost", "rmi"),
):
    """Load :class:`pudl.PudlTabl` from cache or create a new one."""
    if not cache_path.exists():
        cache_path.mkdir()

    file = cache_path / "pdltbl"
    if not file.with_suffix(".zip").exists() or clobber:
        file.with_suffix(".zip").unlink(missing_ok=True)
        LOGGER.info("Rebuilding PudlTabl")
        pudl_out = PudlTabl(
            sa.create_engine(get_defaults()["pudl_db"]),
        )
        for table in tables:
            getattr(pudl_out, table)()
        DataZip.dump(pudl_out, file)
        return pudl_out

    try:
        pudl_out = DataZip.load(file, PudlTabl)
    except Exception as exc:
        LOGGER.error("Loading PudlTabl from file failed %r", exc)
        return get_pudl_tabl(clobber=True)
    else:
        LOGGER.info("Loading PudlTabl from file")
        return pudl_out
