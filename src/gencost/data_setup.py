import json
import logging
import shutil

import pandas as pd
import pyarrow
import pyarrow.dataset as ds
from etoolbox.utils.misc import download
from etoolbox.utils.pudl import CACHE_PATH as ETB_CACHE_PATH
from etoolbox.utils.pudl import pd_read_pudl as etb_pd_read_pudl
from etoolbox.utils.remote_zip import RemoteIOError, RemoteZip
from platformdirs import user_cache_path
from tqdm.auto import tqdm
from tqdm.contrib.logging import logging_redirect_tqdm

from gencost.constants import PUDL_RELEASE_VERSION
from gencost.package_data import PACKAGE_PATH

CACHE_PATH = user_cache_path("gencost", "rmi")
logger = logging.getLogger(__name__)


def make_cache_path():
    if not CACHE_PATH.exists():
        CACHE_PATH.mkdir()


def retrieve_pudl_tabl():
    pudl_path = CACHE_PATH / "pdltbl.zip"
    if pudl_path.exists() and pudl_path.stat().st_atime < 1689358941:
        pudl_path.unlink()
    if not pudl_path.exists():
        download(
            "https://github.com/rmi-electricity/easy-data/"
            "blob/main/pdltbl.zip?raw=true",
            pudl_path,
        )


def wage_data(
    years=(1994, 2023), clobber=False, base_url="https://data.bls.gov/cew/data/files/"
):
    """Download wage data for scaling cost data by year and state.

    Args:
        years: years of data that will be downloaded
        clobber: re-download data even if cached version exists
        base_url: base url to download from

    Returns:

    """
    par = PACKAGE_PATH / "wage_data.parquet.gzip"
    if par.exists() and not clobber:
        return pd.read_parquet(par)
    else:
        path = CACHE_PATH / "temp"
        path.mkdir(parents=True, exist_ok=True)
        with logging_redirect_tqdm():
            for y in tqdm(range(*years), desc="Downloading wage data"):
                url = base_url + f"{y}/csv/{y}_annual_by_industry.zip"
                try:
                    with RemoteZip(url) as zipf:
                        file, *_ = (x for x in zipf.namelist() if " 2211 " in x)
                        zipf.extract(file, path / f"{y}.csv")
                except RemoteIOError:
                    logger.error("Unable to download wage data for %s from %s", y, url)

        data = (
            ds.dataset(
                path,
                format="csv",
                schema=pyarrow.schema(
                    {
                        "area_fips": pyarrow.string(),
                        "agglvl_code": pyarrow.int32(),
                        "year": pyarrow.int32(),
                        "annual_avg_emplvl": pyarrow.int64(),
                        "avg_annual_pay": pyarrow.int64(),
                    }
                ),
            )
            .to_table(filter=ds.field("agglvl_code") == 56)
            .to_pandas()
            .astype(
                {
                    "annual_avg_emplvl": "Int64",
                    "avg_annual_pay": "Float64",
                    "area_fips": "Int64",
                }
            )
        )
        data.to_parquet(par)
        shutil.rmtree(path)
        return data


def pd_read_pudl(
    table_name: str, release: str = "nightly", token: dict | str | None = None, **kwargs
) -> pd.DataFrame:
    """Required for debugging because of an issue in gcsfs/s3fs"""
    try:
        return etb_pd_read_pudl(table_name, release=release, token=token, **kwargs)
    except TypeError:
        return pd.read_parquet(_cache_path(table_name))


def _cache_path(table_name: str):
    """Determine the local path for a cached PUDL table if it exists.

    Args:
        table_name: name of pudl table

    Returns: Path of cached PUDL table

    """

    base = (
        "pudl.catalyst.coop"
        if "aws" in str(ETB_CACHE_PATH)
        else "parquet.catalyst.coop"
    )
    cache_info_path = ETB_CACHE_PATH / "cache"
    if cache_info_path.exists():
        with open(cache_info_path) as f:
            cache_data = json.loads(f.read())
        if table_cache_data := cache_data.get(
            f"{base}/{PUDL_RELEASE_VERSION}/{table_name}.parquet"
        ):
            return ETB_CACHE_PATH / table_cache_data["fn"]
    return None


def main():
    make_cache_path()
    retrieve_pudl_tabl()


if __name__ == "__main__":
    main()
