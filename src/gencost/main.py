import argparse
import logging
import shutil
import subprocess
from pathlib import Path
from time import time

import pandas as pd
from platformdirs import user_cache_path, user_documents_path

from gencost.crosswalk import Crosswalk
from gencost.waterfall import DataBySubplant

logger = logging.getLogger(__name__)


def main():
    """Run the full gencost process."""
    parser = argparse.ArgumentParser(description="Run gencost.")
    parser.add_argument(
        "-o, --out_file",
        type=str,
        help="file path for saving outputs, default is ~/Documents/gencost/fom_som_vom.parquet",
        default=None,
        required=False,
        dest="out_file",
    )
    args = parser.parse_args()

    if args.out_file is None:
        # directory for final results if no file/location provided
        doc_dir = user_documents_path() / "gencost"
        if not doc_dir.exists():
            doc_dir.mkdir(parents=True)
        result_path = doc_dir / "fom_som_vom.parquet"
    else:
        _ofp = Path(args.out_file).absolute()
        result_path = (_ofp / "fom_som_vom" if _ofp.is_dir() else _ofp).with_suffix(
            ".parquet"
        )

    start_time = time()

    # directory of R scripts inside gencost
    r_scripts = Path(__file__).parent / "r_scripts"

    # directory for intermediate outputs and sharing between R and Python
    temp_dir = user_cache_path("gencost", "rmi") / "temp"
    if not temp_dir.exists():
        temp_dir.mkdir(parents=True)

    try:
        logger.info("Setting up python data processing objects")
        xwalk = Crosswalk()
        data_by_subplant = DataBySubplant(xwalk)

        logger.info("Creating data_by_subplant")
        data_by_subplant.merge_all().to_parquet(temp_dir / "data_by_subplant.parquet")

        logger.info("Installing R packages")
        _ = subprocess.run(["Rscript", r_scripts / "module_setup.R"])
        # just an arg parsing example
        _ = subprocess.run(["Rscript", r_scripts / "test.R", "--file", "weeee"])

        logger.info("Starting regressions")
        result = subprocess.run(["Rscript", r_scripts / "1_elt.R", "--file", "path"])
        logger.info("%s", result.stdout)

        logger.info("Doing more stuff")
        result = subprocess.run(
            ["Rscript", r_scripts / "2_elt_specific_to_linear_regressions.R"]
        )
        logger.info("%s", result.stdout)

        ...

        # not quite sure about this part but the idea is that the final result gets
        # saved to result_path
        out = data_by_subplant.get_eternally_present_by_generator().merge(
            vom_fom_som=pd.read_csv(temp_dir / "results_new_data.csv").assign(
                report_date=lambda x: pd.to_datetime(
                    x["report_date"], format="%Y-%m-%d"
                )
                + pd.DateOffset(days=1)
            ),
            on=["plant_id_eia", "generator_id", "report_date", "prime_mover"],
            how="left",
            indicator=True,
        )

        out.to_parquet(result_path)

    finally:
        # only delete temp directory if results were exported in the time since
        # the run began (later we can figure out how to use good parts of
        # incomplete runs)
        if result_path.exists() and result_path.stat().st_birthtime > start_time:
            shutil.rmtree(temp_dir)

        # if we totally failed and produced nothing, clean up
        if not any(temp_dir.iterdir()):
            temp_dir.rmdir()


if __name__ == "__main__":
    main()
