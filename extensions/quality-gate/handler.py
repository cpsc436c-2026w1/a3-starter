"""Quality gate: runs your scenarios on a branch table each time the table commits.

Trigger: S3 ObjectCreated on s3://<bucket>/branch/tables/, suffix .metadata.json. Every Iceberg commit (INSERT,
MERGE, DELETE, OPTIMIZE, a Glue job's write) writes exactly one new metadata file after its data files, so the event
means "this table just changed, and its data is complete". The scenarios and steps live in your bucket under
branch/checks/features/, so you change them without redeploying. Results go to branch/checks/results/<table>/,
outside branch/tables/, so writing them never triggers the gate again."""
import datetime, json, os, shutil, sys, urllib.parse
import boto3
from behave.__main__ import main as behave_main

s3 = boto3.client("s3")
HERE = os.path.dirname(os.path.abspath(__file__))


def table_from_key(key):
    """branch/tables/branch.db/receipts/metadata/x.metadata.json or branch/tables/members/metadata/... -> branch.receipts"""
    parts = key.split("/")
    i = parts.index("metadata")
    return "branch." + parts[i - 1]


def fetch_features(bucket, dest):
    shutil.rmtree(dest, ignore_errors=True)
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix="branch/checks/features/"):
        for o in page.get("Contents", []):
            rel = o["Key"][len("branch/checks/features/"):]
            if rel and not rel.endswith("/"):
                path = os.path.join(dest, rel)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                s3.download_file(bucket, o["Key"], path)


def handler(event, context):
    out = []
    for rec in event.get("Records", []):
        bucket = rec["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(rec["s3"]["object"]["key"])
        table = table_from_key(key)
        short = table.split(".")[1]
        feats = "/tmp/features"
        fetch_features(bucket, feats)
        os.environ["INTERNALS_DIR"] = os.path.join(HERE, "iceberg-internals")
        report = "/tmp/behave.json"
        code = behave_main([feats, "-D", f"TABLE={table}", "--tags", f"@{short},@all", "--format", "json",
                            "--outfile", report, "--no-capture", "--no-summary"])
        res = json.load(open(report))
        scen = []
        for f in res:
            for e in f.get("elements", []):
                if e.get("type") != "scenario":
                    continue
                msg = next((" ".join(s["result"].get("error_message", [])) if isinstance(s["result"].get("error_message"), list)
                            else str(s["result"].get("error_message", ""))
                            for s in e.get("steps", []) if s.get("result", {}).get("status") in ("failed", "error")), "")
                scen.append({"scenario": e["name"], "status": e.get("status", "skipped"), "detail": msg.replace("ASSERT FAILED: ", "")})
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        result = {"table": table, "commit": key, "checked_at": now, "passed": code == 0, "scenarios": scen}
        s3.put_object(Bucket=bucket, Key=f"branch/checks/results/{short}/{now}.json",
                      Body=json.dumps(result, indent=1).encode(), ContentType="application/json")
        print(json.dumps(result))
        out.append(result)
    return out
