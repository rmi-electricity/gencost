"""A tool for estimating generator unit costs from public utility data."""
import logging
from importlib.metadata import PackageNotFoundError, version

# In order for the package modules to be available when you import the package,
# they need to be imported here somehow. Not sure if this is best practice though.
import gencost.cli
import gencost.dummy  # noqa: F401

# Create a root logger for use anywhere within the package.
logger = logging.getLogger(__name__)
logger.addHandler(logging.NullHandler())

__author__ = "RMI"
__contact__ = "aengel@rmi.org"
__maintainer__ = "RMI"
__license__ = "BSD 3-Clause License"
__maintainer_email__ = "...@rmi.org"
__docformat__ = "restructuredtext en"
__description__ = "A tool for estimating generator unit costs from public utility data."
__long_description__ = """
A tool for estimating generator unit costs from public utility data.
"""

try:
    __version__ = version("rmi.gencost")
except PackageNotFoundError:
    logger.warning("Version unknown because package is not installed.")
    __version__ = "unknown"

__projecturl__ = "https://github.com/rmi-electricity/gencost"
__downloadurl__ = "https://github.com/rmi-electricity/gencost"
