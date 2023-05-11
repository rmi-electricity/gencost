import logging

from etoolbox.utils.misc import download
from platformdirs import user_cache_path

CACHE_PATH = user_cache_path("gencost", "rmi")
logger = logging.getLogger(__name__)


def make_cache_path():
    if not CACHE_PATH.exists():
        CACHE_PATH.mkdir()


def retrieve_pudl_tabl():
    pudl_path = CACHE_PATH / "pdltbl.zip"
    if pudl_path.exists() and pudl_path.stat().st_atime < 1683847420:
        pudl_path.unlink()
    if not pudl_path.exists():
        download(
            "https://github.com/rmi-electricity/easy-data/"
            "blob/main/pdltbl.zip?raw=true",
            pudl_path,
        )


def main():
    make_cache_path()
    retrieve_pudl_tabl()


if __name__ == "__main__":
    main()
