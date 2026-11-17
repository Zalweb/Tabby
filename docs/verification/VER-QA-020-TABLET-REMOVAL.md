# QA-020 — User-authorized tablet removal

```json verification-metadata
{
  "id": "VER-QA-020-TABLET-REMOVAL",
  "task_ids": [
    "QA-020"
  ],
  "timestamp": "2026-11-14T15:28:51.937+08:00",
  "tested_commit": "c6e53c89c0fde9ecd6f527941496fb17ca9ba15b",
  "dirty_tree": true,
  "environment": "Paired physical Lenovo TB321FU, hardware identity matched; current Android user0",
  "commands": [
    "adb -s <verified paired tablet> shell getprop ro.serialno",
    "adb -s <verified paired tablet> shell am get-current-user",
    "adb -s <verified paired tablet> shell pm list packages --user 0 com.zalweb.tabby",
    "adb -s <verified paired tablet> shell pm uninstall --user 0 <each exact Tabby package>",
    "repeat exact current-user package inventory"
  ],
  "checks": [
    {
      "category": "tablet-removal",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

User explicitly requested removing the preserved old Tabby. com.zalweb.tabby: already_absent; com.zalweb.tabby.usbtest: removed_with_local_data. Both exact packages were absent in the final current-user inventory. The test-copy removal used no keep-data flag, so its local data was removed. The main app was already absent; its prior removal/data handling was not inspected. No replacement installed.

## Evidence

Hardware identity matched the previously paired physical Lenovo TB321FU; primary user0 confirmed. The test-copy removal acknowledgment and both package postconditions are retained in ignored local qa020-removal-result.json. No private application data was read or stored.

## Limits and next action

Current-primary-user Android uninstall/package checks only. No cloud account/history deletion or emulator change. Existing production readiness gates remain open; finish provider and final candidate acceptance before clean installation. Independent review remains unverified.
