GenCost: A tool for estimating generator unit costs from public utility data
=======================================================================================


.. image:: https://github.com/rmi-electricity/gencost/workflows/tox-pytest/badge.svg
   :target: https://github.com/rmi-electricity/gencost/actions?query=workflow%3Atox-pytest
   :alt: Tox-PyTest Status

.. image:: https://github.com/rmi-electricity/gencost/workflows/docs/badge.svg
   :target: https://rmi-electricity.github.io/gencost/
   :alt: GitHub Pages Status

.. image:: https://img.shields.io/badge/code%20style-black-000000.svg
   :target: https://github.com/psf/black>
   :alt: Any color you want, so long as it's black.

.. image:: https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/charliermarsh/ruff/main/assets/badge/v2.json
    :target: https://github.com/astral-sh/ruff
    :alt: Ruff

.. image:: https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/astral-sh/uv/main/assets/badge/v0.json
    :target: https://github.com/astral-sh/uv
    :alt: uv

.. readme-intro

Development install
=======================================================================================
To create an environment for GenCost, navigate to the repo folder in terminal and run:

With uv
--------
To create an environment for GenCost, navigate to the repo folder in terminal and run:

.. code-block:: bash

   uv sync --all-extras
   pre-commit install

If the pre-commit command doesn't work see
`here <https://github.com/rmi-electricity/.github-private/blob/main/profile/notes_on_dev_env.md>`__
for development environment setup guidance.


With mamba
-----------
To create an environment for GenCost, navigate to the repo folder in terminal and run:

.. code-block:: bash

   mamba update mamba
   mamba env create --name gencost --file environment.yml

Then setup some tools...

.. code-block:: bash

   mamba activate gencost
   pre-commit install

Now everything should be ready!


Development guidance
=======================================================================================

See
`git guidance <https://github.com/rmi-electricity/.github-private/blob/main/profile/notes_on_git.md>`_
and
`notes on tests and linters <https://github.com/rmi-electricity/.github-private/blob/main/profile/notes_on_tests_and_linters.md>`_.

GenCost Clustering and Regressions Summary
=======================================================================================
In order to predict what we call the vom, fom, and som of any new data set, we've written this suite of scripts.
For an in-depth discussion of what these scripts do,
`see <https://rockmtnins.sharepoint.com/:w:/r/sites/UTF/_layouts/15/Doc.aspx?action=edit&sourcedoc=%7B96384017-d470-4f7a-9ca1-49a27957d20a%7D&wdOrigin=TEAMS-ELECTRON.teamsSdk.openFilePreview&wdExp=TEAMS-CONTROL&web=1>`__.

Please note that two tables are generally referred to here:
1. DataBySubplant
2. NewData (this is basically a reference to either EternallyPresent or HistoricalData-- you can punch in whichever you want, as long as you are consistent as you run through these five scripts.


INSTRUCTIONS:

0. module_setup.R
	This script simply lists all of the libraries that you'll need. Please make sure you have all of them installed.
1. module_initial_transformations.R
	Create variables that we'll need as we move forward.
2. module_pca.R
	DataBySubplant has a lot of co-linearity in its variables; use PCA to decompose our data into a few useful components.
3. module_clusters.R
	We've decided how many clusters we'll use per prime_mover type: now, fit clustering models to the data.
4. module_regressions.R
	Find the optimal linear regression model for each cluster.
5. module_final_transformations.R
	Calculate the vom, fom, and som for each row of our new data set, and export it to disk.
