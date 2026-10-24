"""Steps for your branch lake's scenarios. Each step runs a small Athena query (see ../../../iceberg-internals).
The table under test comes from -D TABLE=branch.<table> (the Lambda sets it from the commit that triggered it)."""
import os, sys
from behave import given, then

sys.path.insert(0, os.environ.get("INTERNALS_DIR", os.path.join(os.path.dirname(__file__), "..", "..", "..", "iceberg-internals")))
import internals  # noqa: E402


@given("the table that was just committed")
def step_table(context):
    context.table_name = context.config.userdata.get("TABLE") or os.environ.get("TABLE")
    assert context.table_name, "set TABLE=branch.<table> (-D TABLE=… or the TABLE environment variable)"


@then('no row has {condition}')
def step_no_row(context, condition):
    n = int(internals.query(f"SELECT count(*) FROM {context.table_name} WHERE {condition}")[0][0])
    assert n == 0, f"{n} rows have {condition}"


@then('the query "{sql}" returns {expected:d}')
def step_query(context, sql, expected):
    got = int(internals.query(sql.replace("{table}", context.table_name))[0][0])
    assert got == expected, f"returned {got}, expected {expected}"


@then("the table has at most {n:d} snapshots")
def step_snapshots(context, n):
    got = internals.snapshot_count(context.table_name)
    assert got <= n, f"{got} snapshots: VACUUM has not expired the old ones"


@then("the table has at most {n:d} data files")
def step_files(context, n):
    got = len(internals.data_files(context.table_name))
    assert got <= n, f"{got} data files: OPTIMIZE has not merged them"


@then("no data file is smaller than {mb:g} MB")
def step_small_files(context, mb):
    small = [f for f in internals.data_files(context.table_name) if f[2] < mb * 1e6]
    assert not small, f"{len(small)} files under {mb} MB, the smallest {min(f[2] for f in small) / 1e6:.3f} MB"


@then("no data file has more than {n:d} row groups")
def step_row_groups(context, n):
    files = internals.data_files(context.table_name)
    known = [f for f in files if f[3] is not None]
    if not known:
        context.scenario.skip("no file records its row groups (split_offsets); see iceberg-internals --footer")
        return
    many = [f for f in known if f[3] > n]
    assert not many, f"{len(many)} files with more than {n} row groups, the most {max(f[3] for f in many)}"


@then("the data files do not overlap on {column}")
def step_sorted(context, column):
    pairs = internals.overlapping_files(context.table_name, column)
    assert not pairs, f"{len(pairs)} pairs of files in one partition overlap on {column}: a filter on it cannot skip them"
