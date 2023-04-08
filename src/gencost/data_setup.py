import logging
from pathlib import Path

import requests
from platformdirs import user_cache_path
from tqdm.auto import tqdm
from tqdm.contrib.logging import logging_redirect_tqdm

CACHE_PATH = user_cache_path("gencost", "rmi")
logger = logging.getLogger(__name__)


def make_cache_path():
    if not CACHE_PATH.exists():
        CACHE_PATH.mkdir()


def download(url: str, fname: Path):
    resp = requests.get(url, stream=True)  # noqa: S113
    total = int(resp.headers.get("content-length", 0))
    # Can also replace 'file' with an io.BytesIO object
    with (
        logging_redirect_tqdm(),
        open(fname, "wb") as file,
        tqdm(
            desc="Downloading " + fname.name,
            total=total,
            unit="iB",
            unit_scale=True,
            unit_divisor=1024,
        ) as bar,
    ):
        for data in resp.iter_content(chunk_size=1024):
            size = file.write(data)
            bar.update(size)


def retrieve_pudl_tabl():
    pudl_path = CACHE_PATH / "pdltbl.zip"
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
