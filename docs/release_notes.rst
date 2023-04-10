=======================================================================================
GenCost Release Notes
=======================================================================================

.. _release-v0-1-0:

---------------------------------------------------------------------------------------
0.1.0 (2023-XX-XX)
---------------------------------------------------------------------------------------

What's New?
^^^^^^^^^^^
*  Setting things up...
*  Remove ``conda`` from GHA process to avoid unnecessary duplication. We now no longer
   use PUDL to make a ``PudlTabl``, for now, we download a serialized one from
   `another repo <https://github.com/rmi-electricity/easy-data>`_.
*  Replace all linters with :mod:`ruff`.
*  Bring gencost related data pre-processing over from
   `patio <https://github.com/rmi-electricity/patio-model>`_.
