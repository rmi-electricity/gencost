import pytest


@pytest.mark.skip(reason="not yet implemented")
@pytest.mark.script_launch_mode("inprocess")
def test_gencost_full(script_runner) -> None:
    """Run each deployed console script with --help as a basic test.

    The script_runner fixture is provided by the pytest-console-scripts plugin.
    """
    ret = script_runner.run(["gencost"], print_result=False)
    assert ret.success  # nosec: B101
