"""Load or create PUDL objects."""
import logging
from pathlib import Path

import sqlalchemy as sa
from etoolbox.datazip import DataZip
from platformdirs import user_cache_path

logger = logging.getLogger(__name__)
CACHE_PATH = user_cache_path("gencost", "rmi")


def get_pudl_tabl(
    tables=(
        "gf_eia923",
        "gen_original_eia923",
        "bf_eia923",
        "gens_eia860",
        "plants_eia860",
        "epacamd_eia",
    ),
    clobber: bool = False,
    cache_path: Path = CACHE_PATH,
):
    """Load :class:`pudl.PudlTabl` from cache or create a new one.

    Args:
        tables: tuple of tables to load from :class:`pudl.PudlTabl`, their names must
            be methods on :class:`pudl.PudlTabl`.
        clobber: if True, replace an existing cache if it exists.
        cache_path: Where to cache the :class:`pudl.PudlTabl`, by default, we use the
            location determined by :mod:`platformdirs`.

    Returns:
        :class:`pudl.PudlTabl` with requested tables loaded.
    """
    try:
        from pudl.output.pudltabl import PudlTabl
        from pudl.workspace.setup import get_defaults
    except ModuleNotFoundError:
        logger.error("Cannot create PudlTabl because PUDL is not installed.")
        return None
    else:
        if not cache_path.exists():
            cache_path.mkdir()

        file = cache_path / "pdltbl"
        if not file.with_suffix(".zip").exists() or clobber:
            file.with_suffix(".zip").unlink(missing_ok=True)
            logger.info("Rebuilding PudlTabl")
            pudl_out = PudlTabl(
                sa.create_engine(get_defaults()["pudl_db"]),
            )
            for table in tables:
                try:
                    getattr(pudl_out, table)()
                except AttributeError as exc:
                    logger.error("Unable to load %s. %r", table, exc)
            DataZip.dump(pudl_out, file)
            return pudl_out

        try:
            pudl_out = DataZip.load(file, PudlTabl)
        except Exception as exc:
            logger.error("Loading PudlTabl from file failed %r", exc)
            return get_pudl_tabl(clobber=True)
        else:
            logger.info("Loading PudlTabl from file")
            return pudl_out
