# Solution notes — Fundo Data Engineer

## Decisions and scope

I chose SQLite + DuckDB + Python to keep the environment credential-free and small. SQLite is a relational source stand-in; DuckDB provides a local analytical warehouse. This deliberately does not claim SQL Server or BigQuery parity. The pipeline prioritizes a reliable, inspectable change log, atomic checkpoints, deterministic identity decisions, and visible reconciliation failures over a production-grade connector.

## Incremental movement and per-table strategy

| Table | Strategy | Reason / trade-off |
|---|---|---|
| `customers` | CDC log, keyed upsert/delete | Mutable profile; current-state table. `merged_into` preserves an auditable redirect. |
| `advances` | CDC log, keyed upsert/delete | Status and funding state can change; funded/paid-off state gates identity merges. |
| `transactions` | CDC log, keyed upsert/delete | Large, mostly append-only table. Incremental movement avoids recurring full copies; a production version would normally treat posted facts as immutable and handle corrections as explicit adjustments. |
| `cards` | CDC log, keyed upsert/delete | Mutable ownership; reassignment must be propagated with the customer merge. |
| `customer_history` | CDC log, append-only versions | Preserve history; production should reject updates/deletes and retain event-time ordering. |
| `scratch_import` | Excluded | No owner or consumer; moving it wastes storage and obscures the supported contract. It is intentionally not part of warehouse completeness checks. |

The sync uses per-table sequence checkpoints. Mutations and checkpoint advancement are committed in one warehouse transaction, so a mid-run exception rolls back both. Replaying events uses primary-key upserts and deletes, making reruns idempotent. This sample has explicit change-log writes in the demo path; it does **not** guarantee capture for arbitrary direct SQL writers. Production must use SQL Server CDC/Change Tracking or audited triggers, including delete capture.

## Duplicate customer policy

**Identity evidence:** an exact, non-empty `external_customer_id` match is the only automatic merge key in this demo. It is intended to represent a source-system-issued immutable ID. **Suggestive only:** name, email, phone, and address-like/contact fields are not sufficient identity evidence; emails can be shared, malformed, recycled, or mistyped. The sample deliberately includes same-name/same-email customers with different external IDs to demonstrate why fuzzy matching is unsafe.

- A customer with a `funded` or `paid_off` advance is protected. If exactly one record in an exact-ID group is protected, it survives. If multiple records are protected, the group is flagged ambiguous and not merged. (The synthetic dataset includes separately protected records to make this policy visible.)
- Test accounts are excluded from merging using an explicit test flag and a short exact allowlist of known test addresses. We do not use broad `LIKE '%test%'`, so `Testerman` remains a real person. A production policy should rely on a dedicated test-account flag/tenant marker rather than email heuristics.
- Malformed contacts are flagged by inspection but not silently rewritten. In the seed, `marta@@example` and `bad-phone` are malformed examples; identity and financial history must not be altered as a side effect of contact cleanup. Production would quarantine validation outcomes and route correction to a controlled process.
- Cards and transactions owned by a merged customer are reassigned to the canonical customer and their changes are logged for downstream sync. A wrong reassignment can expose payment instruments or corrupt customer-level financial reporting, so uncertain groups are not auto-merged.
- The surviving row records `merged_into` on duplicates and an identity map records the reason. The compact sample does not implement a fully transactional merge service or all foreign-key validation. Production should add a partial unique constraint for active external IDs after cleanup, preserve the old IDs as aliases, and make merge + dependent-key reassignment one audited source transaction.

## Correctness checks and evidence

The checks compare source and warehouse row counts and primary-key sets, reporting missing keys and stale warehouse keys. The demo intentionally deletes a warehouse transaction and shows a failing check, then performs an operator-triggered table reconciliation to repair it. Counts alone are not sufficient for production: checks should also compare deterministic hashes or selected critical columns and financial aggregates (advance totals, transaction totals, card ownership), report freshness/lag, and alert on failure.

**Measured locally:** the run prints event counts and elapsed milliseconds measured with `perf_counter` on the current container. Exact numbers depend on machine and Docker overhead; use the actual output, not a hard-coded benchmark. **Not measured:** cloud billing, BigQuery bytes processed, SQL Server log impact, or production throughput. No performance or cost claim is inferred from this tiny synthetic fixture.

## Cost impact

Today’s described waste is a full-database daily copy to discover an approximately 1% change rate. Incremental CDC changes transfer work toward changed rows plus checkpoint/reconciliation overhead rather than scanning and moving every row. If the change fraction is 1%, the *idealized changed-row payload* is roughly 1/100 of a full copy, but this is an estimate, not a measured saving: CDC log volume, indexes, deletes, retries, partitioning, query patterns, and BigQuery ingestion/query billing affect the real bill. Keep the full-copy baseline until an apples-to-apples measurement includes source load, bytes moved, warehouse storage and queries.

## Production evolution

1. **First delivery:** SQL Server CDC/Change Tracking capture with durable offsets, replayable batches, dead-letter handling, and an atomic per-table checkpoint. This addresses the main cost and recovery issue without changing the warehouse contract.
2. Add automated reconciliation with primary-key anti-joins, critical-field hashes, business aggregates, freshness SLOs, and alerts; retain a periodic bounded full reconciliation to detect CDC gaps.
3. Move to BigQuery with staging tables and transactional `MERGE` statements, partition large transaction facts by event date, cluster by commonly filtered identifiers, and use partition-aware backfills. Estimate bytes scanned before choosing partitioning.
4. Treat duplicate resolution as a reviewed, audited one-time cleanup followed by permanent identity constraints and an alias/redirect table. Never infer identity from contact similarity alone. Keep test data isolated at ingestion.
5. Add schema contracts, migration tests, PII minimization, least-privilege service accounts, secret management, retention rules for history, operational dashboards, and restore/replay runbooks.

The one-time work is historical duplicate cleanup and initial baseline reconciliation. CDC ingestion, incremental merges, quality checks, alerting, and periodic reconciliation run permanently.
