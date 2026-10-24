"""Quality gate: runs your scenarios on a branch table each time the table commits.

Trigger: S3 ObjectCreated on s3://<bucket>/branch/tables/, suffix .metadata.json. An Iceberg commit (INSERT, MERGE,
DELETE, OPTIMIZE, a Glue job's write) writes its data files, then a new metadata file, then points the Glue catalog at
that file. So the event means "this table is about to change, and its data files are already written": the handler
waits until the catalog points at the new file before it runs the scenarios. The scenarios and steps live in your
bucket under branch/checks/features/, so you change them without redeploying. Results go to
branch/checks/results/<table>/, outside branch/tables/, so writing them never triggers the gate again."""
import datetime, json, os, shutil, subprocess, sys, time, traceback, urllib.parse
import boto3

s3 = boto3.client("s3")
glue = boto3.client("glue")
HERE = os.path.dirname(os.path.abspath(__file__))


def table_from_key(bucket, key):
    """The branch table whose location holds this metadata file; falls back to the folder before metadata/."""
    folder = key[:key.index("/metadata/")]
    for page in glue.get_paginator("get_tables").paginate(DatabaseName="branch"):
        for t in page["TableList"]:
            loc = t.get("StorageDescriptor", {}).get("Location", "").replace(f"s3://{bucket}/", "").rstrip("/")
            if loc == folder:
                return "branch." + t["Name"]
    return "branch." + folder.rsplit("/", 1)[-1]


def wait_for_catalog(short, key, tries=10):
    """Wait until Glue's metadata_location for the table is this file; return what it points at."""
    cur = ""
    for _ in range(tries):
        cur = glue.get_table(DatabaseName="branch", Name=short)["Table"].get("Parameters", {}).get("metadata_location", "")
        if cur.endswith(key):
            break
        time.sleep(3)
    return cur


def fetch_features(bucket, dest):
    shutil.rmtree(dest, ignore_errors=True)
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix="branch/checks/features/"):
        for o in page.get("Contents", []):
            rel = o["Key"][len("branch/checks/features/"):]
            if rel and not rel.endswith("/"):
                path = os.path.join(dest, rel)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                s3.download_file(bucket, o["Key"], path)


def run_behave(table, short, feats, report):
    """behave in a child process: a warm Lambda would otherwise keep the step functions of its first run."""
    if os.path.exists(report):
        os.remove(report)
    env = dict(os.environ, INTERNALS_DIR=os.path.join(HERE, "iceberg-internals"),
               PYTHONPATH=os.pathsep.join([HERE] + sys.path))
    p = subprocess.run([sys.executable, "-m", "behave", feats, "-D", f"TABLE={table}", "--tags", f"@{short},@all",
                        "--format", "json", "--outfile", report, "--format", "plain", "--no-capture", "--no-summary"],
                       env=env, cwd="/tmp", capture_output=True, text=True)
    print(p.stdout[-4000:], p.stderr[-4000:])
    return p.returncode, p.stdout + p.stderr


def scenarios_from(report, plain):
    scen = []
    for f in json.load(open(report)):
        for e in f.get("elements", []):
            if e.get("type") != "scenario":
                continue
            msg = ""
            for s in e.get("steps", []):
                r = s.get("result", {})
                if r.get("status") in ("failed", "error"):
                    m = r.get("error_message", "")
                    msg = "".join(m) if isinstance(m, list) else str(m)
                    break
            status = e.get("status", "skipped")
            if status == "skipped" and not msg:
                tag = f"SKIP Scenario {e['name']}: "  # behave logs the reason given to context.scenario.skip
                msg = next((l.split(tag, 1)[1].strip() for l in plain.splitlines() if tag in l), "skipped")
            scen.append({"scenario": e["name"], "status": status, "detail": msg.replace("ASSERT FAILED: ", "").strip()})
    return scen


def handler(event, context):
    out = []
    for rec in event.get("Records", []):
        bucket = rec["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(rec["s3"]["object"]["key"])
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        version = os.path.basename(key).split(".")[0]  # 00042-<uuid>: unique per metadata file
        result = {"commit": key, "checked_at": now}
        try:
            table = table_from_key(bucket, key)
            short = table.split(".")[1]
            result["table"] = table
            cur = wait_for_catalog(short, key)
            result.update(tested_metadata=cur, is_this_commit=cur.endswith(key))
            feats, report = "/tmp/features", "/tmp/behave.json"
            fetch_features(bucket, feats)
            code, plain = run_behave(table, short, feats, report)
            result["passed"] = code == 0
            result["scenarios"] = scenarios_from(report, plain) if os.path.exists(report) else []
            if not os.path.exists(report):
                result["error"] = plain[-2000:]
        except Exception:
            short = result.get("table", "unknown.unknown").split(".")[1]
            result.update(passed=False, error=traceback.format_exc()[-2000:])
        s3.put_object(Bucket=bucket, Key=f"branch/checks/results/{short}/{now}-{version}.json",
                      Body=json.dumps(result, indent=1).encode(), ContentType="application/json")
        print(json.dumps(result))
        out.append(result)
    return out
