# wsd_feed_relay

Mirror of the public DATA.GOV.HK file "Temporary Water Suspension Notices" (Water Supplies Department).

The workflow `mirror` runs every 30 minutes on GitHub's servers, because the Water Supplies Department
server does not answer our own servers. It downloads the file, checks it (HTTP 200, over 10 KB, the exact header
row, not a web page) and commits it. `wsms_open_data.csv` is the copy; `status.json` says when it was last checked
and holds its hash, so a reader can tell how old the copy is. A failed check commits nothing and fails the run.

Source: DATA.GOV.HK, "Temporary Water Suspension Notices", Water Supplies Department. Terms: https://data.gov.hk/en/terms-and-conditions
