# Interrupted mutation attempt

The full test run passed before the audit wrapper automatically began mutation testing.
The creator asked to skip mutation testing and have Claude audit. The running mutation
process and its compiler child were terminated. The clean baseline passed 184 tests;
4 of 90 planned mutations completed before cancellation. The new batch mutations
were not reached. This is incomplete evidence, not a passed mutation audit.

The top-level historical mutation reports were restored from commit ff5e952 to avoid
mixing partial 3.2.0 results with the earlier complete 3.1.0 campaign. Current validation
status is in audit/results.json and audit/BATCH-BIDDING-2026-09-08.md.
