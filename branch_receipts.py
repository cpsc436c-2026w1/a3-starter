import sys
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F

# Job parameters: --BUCKET 436c-glue-<account> --DAY 2026-10-16
args = getResolvedOptions(sys.argv, ["JOB_NAME", "BUCKET", "DAY"])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

RAW = f"s3://{args['BUCKET']}/branch/raw/receipts/dt={args['DAY']}/"
# glue_catalog is this job's name for your Glue Data Catalog (set in the job's Spark settings);
# Athena shows the same table as branch.receipts
TABLE = "glue_catalog.branch.receipts"

# 1. Read the day's till export: one CSV file with a header row
raw = spark.read.option("header", "true").csv(RAW)

# 2. Give each column the table's type
receipts = raw.select(
    F.col("receipt_id"),
    F.col("line_no").cast("int"),
    F.to_timestamp("sold_at", "yyyy-MM-dd HH:mm:ss").alias("sold_at"),
    F.col("store_id").cast("int"),
    F.col("checkout_lane").cast("int"),
    F.col("household_id").cast("bigint"),
    F.col("product_code"),
    F.col("quantity").cast("int"),
    F.col("unit_price_eur").cast("double"),
    F.col("discount_eur").cast("double"),
    F.col("line_total_eur").cast("double"),
    F.col("payment_method"),
)

# 32 Spark partitions, one task each, so the write runs in parallel
receipts = receipts.repartition(32)

# 3. Write the rows into the Iceberg table branch.receipts, partitioned by day of sale.
#    The first run creates the table; every later run appends to it.
exists = spark.sql("SHOW TABLES IN glue_catalog.branch LIKE 'receipts'").count() > 0
if exists:
    receipts.writeTo(TABLE).append()
else:
    (receipts.writeTo(TABLE)
        .partitionedBy(F.days("sold_at"))
        .tableProperty("format-version", "2")                  # needed for row-level deletes and MERGE
        .tableProperty("write.distribution-mode", "none")      # each task writes its own rows straight out
        .tableProperty("write.spark.fanout.enabled", "true")   # lets each task write to many day partitions
        .create())

job.commit()
