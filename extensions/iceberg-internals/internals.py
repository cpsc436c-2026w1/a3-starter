#!/usr/bin/env python3
"""Look inside an Iceberg table through Athena's metadata tables: snapshots, data files, row groups, sort.

    python3 internals.py branch.receipts [--sort-column sold_at]

Every number comes from the table's metadata, not from its rows, so each query reads only metadata and bills
Athena's 10 MB minimum. The quality gate (../quality-gate) imports these functions for its scenarios.

- snapshots: one row per commit (`"<table>$snapshots"`); a long list is history VACUUM has not expired yet.
- data files: `"<table>$files"`, one row per data file with its size and rows. Many small files are what OPTIMIZE merges.
- row groups: `split_offsets` in `$files` lists where each Parquet row group starts, so its length is the row-group
  count. Spark's Iceberg writer (your Glue jobs) records them; Athena's OPTIMIZE output does not. For a file without
  them, `--footer s3://…/file.parquet` reads the count from the file's own footer (needs `pip install --user pyarrow`).
- sort: `lower_bounds` and `upper_bounds` in `$files` give each file's minimum and maximum per column (keyed by the
  column's field id). Files whose ranges overlap on a column are not sorted by it across files: a filter on a value
  in the shared range must read every file that covers it (tutorial 2's rides_sorted against rides).
"""
import os, sys, time
import boto3

WORKGROUP = os.environ.get("WORKGROUP", "primary")
_ath = None


def athena():
    global _ath
    if _ath is None:
        _ath = boto3.client("athena", region_name="ca-central-1")
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


def _describe(table):
    """[(column, type)] in DESCRIBE order, partition section left out."""
    cols = []
    for r in query(f"DESCRIBE {table}"):
        line = (r[0] or "") if r else ""
        if line.startswith("#"):
            if cols:
                break  # the partition section repeats columns
            continue
        parts = [x.strip() for x in line.split("\t")]
        if parts and parts[0]:
            cols.append((parts[0], parts[1].lower() if len(parts) > 1 else "string"))
    return cols


def field_id(table, column):
    """Iceberg field id of a column: its position in DESCRIBE, counting from 1. True while the table has only plain
    columns (no struct, map or array), none was dropped, and new ones were added at the end (ADD COLUMNS does that)."""
    return [c for c, _ in _describe(table)].index(column) + 1


def _convert(col_type):
    """Athena returns bounds as text; compare them as the column's type ("100" < "99" as text)."""
    if col_type in ("tinyint", "smallint", "int", "integer", "bigint"):
        return int
    if col_type in ("float", "real", "double") or col_type.startswith("decimal"):
        return float
    return str  # date, timestamp, string: their text sorts in the right order


def files_by_partition(table, column):
    """{partition: [(min, max, file_path)]} for the data files that record bounds on `column`."""
    cols = _describe(table)
    fid = [c for c, _ in cols].index(column) + 1
    conv = _convert(dict(cols)[column])
    part = '"partition"' if _has_partition(table) else "''"
    rows = query(f"SELECT file_path, {part}, lower_bounds[{fid}], upper_bounds[{fid}] FROM {_meta(table, 'files')}")
    by_part = {}
    for path, p, lo, hi in rows:
        if lo is not None and hi is not None:
            by_part.setdefault(p, []).append((conv(lo), conv(hi), path))
    return by_part


def overlapping_files(table, column, by_part=None):
    """Pairs of data files in the same partition whose [min, max] ranges on `column` overlap."""
    pairs = []
    for files in (by_part if by_part is not None else files_by_partition(table, column)).values():
        reach = None  # the largest max so far, and its file
        for lo, hi, path in sorted(files):
            if reach and lo <= reach[0]:
                pairs.append((reach[1], path))
            if not reach or hi > reach[0]:
                reach = (hi, path)
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
    print(f"{t}: {snapshot_count(t)} snapshots, {len(files)} data files, {sum(f[1] for f in files)} rows in data files"
          " (rows removed by delete files are still counted until OPTIMIZE)")
    for p, n, b, g in files[:10]:
        print(f"  {b / 1e6:8.2f} MB  {n:>9} rows  {g if g is not None else '?':>3} row groups  {p.rsplit('/', 1)[-1]}")
    if "--sort-column" in sys.argv:
        c = sys.argv[sys.argv.index("--sort-column") + 1]
        bp = files_by_partition(t, c)
        o = overlapping_files(t, c, bp)
        multi = sum(1 for f in bp.values() if len(f) > 1)
        print(f"files overlapping on {c} inside a partition: {len(o)} pairs "
              f"({multi} of {len(bp)} partitions have more than one file to compare)")
