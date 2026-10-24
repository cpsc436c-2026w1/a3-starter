-- Task 1.2: the healthier-basket report. Data source: course (the company lakehouse).
-- Two parts are left for you: the condition that picks Nutri-Score A and B products (____ 1), and the GROUP BY (____ 2).
-- Run it once on its own (record Data scanned and run time), then wrap it, without its final `;`,
-- in the UNLOAD statement from the assignment.

SELECT date_format(c.event_ts, '%Y-%m') AS month,
       CASE WHEN h.is_lyon THEN 'lyon' ELSE 'rest' END AS segment,
       sum(CASE WHEN ____ 1 ____ THEN c.line_total_eur ELSE 0 END) / sum(c.line_total_eur) AS ab_share
FROM course.course_lake.consumption c
JOIN course.course_lake.households h ON c.household_id = h.household_id
LEFT JOIN course.course_lake.catalogue g ON c.product_code = g.code     -- products not in the catalogue count in the total
____ 2 ____
ORDER BY 1, 2;
