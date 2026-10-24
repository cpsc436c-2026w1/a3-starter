# Your branch lake's quality gate. Each scenario names the requirement or the table property it checks.
# Tags pick the tables a scenario applies to: @members, @receipts, @price_events, or @all for every table.
# Two scenarios are given; write your own below them (the assignment's hint lists ideas).
Feature: The branch lake stays correct and cheap after every commit

  Background:
    Given the table that was just committed

  @members
  Scenario: Only Lyon members are copied (R11, data-use rule 1)
    Then no row has is_lyon = false

  @all
  Scenario: History is expired (R51, R90)
    Then the table has at most 5 snapshots
