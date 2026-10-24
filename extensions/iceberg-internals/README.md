# Iceberg internals: what a table's metadata tells you

`internals.py` reads a table's own metadata through Athena's metadata tables, never its rows, so each call bills
Athena's 10 MB minimum at most. Run it in CloudShell from this folder:

```bash
python3 internals.py branch.receipts --sort-column sold_at
```

| What you want to know | Where it comes from | What a bad value means |
|---|---|---|
| How much history the table keeps | `"<table>$snapshots"`: one row per commit | VACUUM has not expired old snapshots (task 4.2) |
| How many data files, and how big | `"<table>$files"`: one row per data file, with `record_count` and `file_size_in_bytes` | many small files: OPTIMIZE has not merged them (task 4.1) |
| How many row groups a file has | `split_offsets` in `$files`: where each Parquet row group starts | many small row groups: each one is a footer entry to read and a unit to skip or not |
| Whether files are sorted by a column | `lower_bounds` and `upper_bounds` in `$files`, per column (keyed by the column's field id) | files whose ranges overlap cannot be skipped by a filter on that column (tutorial 2's sorted rides) |

Two things to know:

- Spark's Iceberg writer (your Glue jobs) records `split_offsets`; Athena's `OPTIMIZE` output does not. For such a
  file, `python3 internals.py --footer s3://…/file.parquet` reads the count from the file's own footer (install the
  reader first: `pip install --user pyarrow`).
- The field id of a column is its position in `DESCRIBE`, counting from 1, as long as no column was dropped
  (task 1.1 used the same rule for `consumption`).

The quality gate (`../quality-gate`) imports these functions in its steps.
