"""Steps for task1_report.feature. REPORT is a local folder of report files or an s3://bucket/prefix/ (JSON Lines,
plain or gzip, as Athena UNLOAD writes them)."""
import gzip, json, os, pathlib
from behave import given, then

FORBIDDEN = {"household_id", "loyalty_card", "receipt_id", "event_id", "line_no"}
MONTHS = [f"{y}-{m:02d}" for y in (2023, 2024, 2025) for m in range(1, 13)]


def _bodies(report):
    if report.startswith("s3://"):
        import boto3
        bucket, _, prefix = report[5:].partition("/")
        s3 = boto3.client("s3")
        for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefix):
            for o in page.get("Contents", []):
                if "/replies/" not in o["Key"] and o["Size"] > 0:
                    yield s3.get_object(Bucket=bucket, Key=o["Key"])["Body"].read()
    else:
        for f in sorted(pathlib.Path(report).rglob("*")):
            if f.is_file() and f.stat().st_size > 0:
                yield f.read_bytes()


@given("the report files in the folder named by REPORT")
def step_report(context):
    report = os.environ.get("REPORT") or context.config.userdata.get("REPORT")
    assert report, "set REPORT to the folder that holds your report files (or pass -D REPORT=...)"
    rows = []
    for body in _bodies(report):
        if body[:2] == b"\x1f\x8b":
            body = gzip.decompress(body)
        rows += [json.loads(line) for line in body.decode("utf-8").splitlines() if line.strip()]
    assert rows, f"no report rows found under {report}"
    context.rows = rows


@then("no row has a member-level column such as household_id or receipt_id")
def step_r70(context):
    found = sorted(set().union(*(r.keys() for r in context.rows)) & FORBIDDEN)
    assert not found, f"member-level columns found: {', '.join(found)}"


@then("every row has exactly the columns month, segment and ab_share")
def step_columns(context):
    bad = [sorted(r.keys()) for r in context.rows if set(r.keys()) != {"month", "segment", "ab_share"}]
    assert not bad, f"{len(bad)} rows have other columns, for example {bad[0]}"


@then("each of the 36 months from 2023-01 to 2025-12 appears once for lyon and once for rest")
def step_rows(context):
    got = [(str(r.get("month")), str(r.get("segment"))) for r in context.rows]
    want = {(m, s) for m in MONTHS for s in ("lyon", "rest")}
    missing, extra = sorted(want - set(got)), sorted(set(got) - want)
    dup = len(got) - len(set(got))
    assert not missing and not extra and not dup, (
        f"{len(got)} rows; missing {len(missing)} {missing[:2]}; unexpected {len(extra)} {extra[:2]}; repeated {dup}")


@then("every ab_share is a number between 0 and 1")
def step_share_range(context):
    bad = []
    for r in context.rows:
        try:
            v = float(r.get("ab_share"))
            if not 0 <= v <= 1:
                bad.append(r)
        except (TypeError, ValueError):
            bad.append(r)
    assert not bad, f"{len(bad)} rows with an ab_share outside 0 to 1, for example {bad[0]}"


@given("head office's key for {name}")
def step_key(context, name):
    import boto3
    body = boto3.client("s3").get_object(Bucket=os.environ.get("KEY_BUCKET", "436c-hq-inbox-940482406111"),
                                         Key=f"keys/{name}.json")["Body"].read()
    context.key = {(r["month"], r["segment"]): r["ab_share"] for r in json.loads(body)["rows"]}


@then("every ab_share is within {tol:g} of head office's figure")
def step_key_match(context, tol):
    got = {}
    for r in context.rows:
        try:
            got[(str(r.get("month")), str(r.get("segment")))] = float(r.get("ab_share"))
        except (TypeError, ValueError):
            pass
    off = [k for k, v in context.key.items() if k not in got or abs(got[k] - v) > tol]
    assert not off, f"{len(off)} shares missing or off by more than {tol}, for example {off[0]}"
