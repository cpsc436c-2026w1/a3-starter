#!/usr/bin/env python3
"""Look inside an Iceberg table through Athena's metadata tables: snapshots, data files, row groups, sort.

    python3 internals.py branch.receipts [--sort-column sold_at]

Every number comes from the table's metadata, not from its rows, so each query is metadata only and bills Athena's
10 MB minimum at most. The quality gate (../quality-gate) imports these functions for its scenarios.

- snapshots: one row per commit (`"<table>$snapshots"`); a long list is history VACUUM has not expired yet.
- data files: `"<table>$files"`, one row per data file with its size and rows. Many small files are what OPTIMIZE merges.
- row groups: `split_offsets` in `$files` lists where each Parquet row group starts, so its length is the row-group
  count. Spark's Iceberg writer (your Glue jobs) records them; Athena's OPTIMIZE output does not. For a file without
  them, `--footer s3://…/file.parquet` reads the count from the file's own footer (needs `pip install --user pyarrow`).
- sort: `lower_bounds` and `upper_bounds` in `$files` give each file's minimum and maximum per column (keyed by the
  column's field id). Files whose ranges overlap on a column are not sorted by it across files, so a filter on that
  column cannot skip any of them (tutorial 2's rides_sorted against rides).
"""
import os, sys, time
import boto3

WORKGROUP = os.environ.get("WORKGROUP", "primary")
_ath = None


def athena():
    global _ath
    if _ath is None:
        _ath = boto3.client("athena", region_name=os.environ.get("AWS_REGION", "ca-central-1"))
    return _ath


def query(sql):
    """Run one statement in the workgroup and return its rows as lists of strings (header removed)."""
    a = athena()
    qid = a.start_query_execution(QueryString=sql, WorkGroup=WORKGROUP)["QueryExecutionId"]
    while (st := a.get_query_execution(QueryExecutionId=qid)["QueryExecution"])["Status"]["State"] in ("QUEUED", "RUNNING"):
        time.sleep(1)
    if st["Status"]["State"] != "SUCCEEDED":
        raise RuntimeError(f"{st['Status']['State']}: {st['Status'].get('StateChangeReason', '')} :: {sql}")
    rows, token = [], None
    while True:
        r = a.get_query_results(QueryExecutionId=qid, **({"NextToken": token} if token else {}))
        rows += [[c.get("VarCharValue") for c in x["Data"]] for x in r["ResultSet"]["Rows"]]
        token = r.get("NextToken")
        if not token:
            return rows[1:]


def _meta(table, kind):
    db, name = table.split(".")
    return f'{db}."{name}${kind}"'


def snapshot_count(table):
    return int(query(f"SELECT count(*) FROM {_meta(table, 'snapshots')}")[0][0])


def data_files(table):
    """[(file_path, record_count, file_size_in_bytes, row_groups)] for every data file of the current snapshot."""
    rows = query(f"SELECT file_path, record_count, file_size_in_bytes, cardinality(split_offsets) FROM {_meta(table, 'files')}")
    return [(p, int(n), int(b), int(g) if g is not None else None) for p, n, b, g in rows]


def field_id(table, column):
    """Iceberg field id of a column: its position in DESCRIBE, counting from 1 (true while no column was dropped)."""
    cols = [r[0].split("\t")[0].strip() for r in query(f"DESCRIBE {table}") if r and r[0] and not r[0].startswith("#")]
    cols = [c for c in cols if c]
    return cols.index(column) + 1


def overlapping_files(table, column):
    """Pairs of data files in the same partition whose [min, max] ranges on `column` overlap."""
    fid = field_id(table, column)
    rows = query(f"SELECT file_path, \"partition\", lower_bounds[{fid}], upper_bounds[{fid}] FROM {_meta(table, 'files')}"
                 if _has_partition(table) else
                 f"SELECT file_path, '', lower_bounds[{fid}], upper_bounds[{fid}] FROM {_meta(table, 'files')}")
    by_part = {}
    for path, part, lo, hi in rows:
        if lo is not None and hi is not None:
            by_part.setdefault(part, []).append((lo, hi, path))
    pairs = []
    for files in by_part.values():
        files.sort()
        for (lo1, hi1, p1), (lo2, hi2, p2) in zip(files, files[1:]):
            if lo2 <= hi1:
                pairs.append((p1, p2))
    return pairs


def _has_partition(table):
    try:
        query(f'SELECT "partition" FROM {_meta(table, "files")} LIMIT 1')
        return True
    except RuntimeError:
        return False


def footer_row_groups(s3_path):
    """Row groups in one Parquet file, from its footer (reads only the footer, not the data)."""
    import pyarrow.parquet as pq
    from pyarrow import fs
    s3 = fs.S3FileSystem(region=os.environ.get("AWS_REGION", "ca-central-1"))
    with s3.open_input_file(s3_path.removeprefix("s3://")) as f:
        return pq.ParquetFile(f).metadata.num_row_groups


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--footer":
        print(footer_row_groups(sys.argv[2]), "row groups")
        sys.exit()
    t = sys.argv[1]
    files = data_files(t)
    print(f"{t}: {snapshot_count(t)} snapshots, {len(files)} data files, {sum(f[1] for f in files)} rows")
    for p, n, b, g in files[:10]:
        print(f"  {b / 1e6:8.2f} MB  {n:>9} rows  {g if g is not None else '?':>3} row groups  {p.rsplit('/', 1)[-1]}")
    if "--sort-column" in sys.argv:
        c = sys.argv[sys.argv.index("--sort-column") + 1]
        o = overlapping_files(t, c)
        print(f"files overlapping on {c} inside a partition: {len(o)} pairs")
