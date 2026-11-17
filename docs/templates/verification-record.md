# Verification record template

Use a fenced json verification-metadata block with fields: id, task_ids (array), checks (array of {category, outcome: passed|failed|unverified}), timestamp, tested_commit, dirty_tree (boolean), environment, commands (array).

## Expected and actual results

Describe scenarios, expected outcomes and observed outcomes.

## Evidence

Link sanitized logs/CI artifacts, identify tool versions, OS, device/API or DB/migration versions.

## Limits and next action

What remains unverified, failures, and exact follow-up.
