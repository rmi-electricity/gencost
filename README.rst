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
