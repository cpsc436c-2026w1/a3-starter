-- Task 3.2: apply the upsert records of day 2's change file to branch.members. Data source: AwsDataCatalog.
-- Run the ALTER TABLE from the assignment first, so branch.members has the column marketing_consent.
-- Two clauses are left for you: what to change in a member that is already in the table (____ 1), and what to
-- insert for a member who is not (____ 2). The assignment's 📋 Commands: MERGE box in task 3.2 shows the shape on another table.
-- household_id is int in branch.members and bigint in branch.raw_households: cast it when you insert.
-- DESCRIBE branch.members and DESCRIBE branch.raw_households list the columns. Each upsert record is a member's whole record.

MERGE INTO branch.members t
USING (SELECT * FROM branch.raw_households WHERE op = 'upsert') c
ON t.household_id = c.household_id
WHEN MATCHED THEN ____ 1 ____
WHEN NOT MATCHED THEN ____ 2 ____;
