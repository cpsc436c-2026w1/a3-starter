# Head office's checks of the task 1 report, as scenarios (Gherkin, L9). The same checks head office runs when your
# report lands in its inbox. Run them on your own report before you deliver it: see the README.
Feature: Healthier-basket report for head office (R20, R70)

  Background:
    Given the report files in the folder named by REPORT

  Scenario: The report holds aggregates only (R70, data-use rule 3)
    Then no row has a member-level column such as household_id or receipt_id

  Scenario: The report has the columns head office asked for (R20)
    Then every row has exactly the columns month, segment and ab_share

  Scenario: One row for each month and segment (R20)
    Then each of the 36 months from 2023-01 to 2025-12 appears once for lyon and once for rest

  Scenario: Every share is a share (R20)
    Then every ab_share is a number between 0 and 1

  @headoffice
  Scenario: Every share matches head office's figure (R20)
    Given head office's key for task1
    Then every ab_share is within 0.0005 of head office's figure
