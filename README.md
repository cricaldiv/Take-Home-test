# Fundo Data Engineer take-home

A fully local SQL Server-to-warehouse exercise. SQLite stands in for SQL Server and DuckDB for BigQuery; Python implements CDC-style incremental movement and reconciliation. No cloud credentials or external data are used.

## Run from a clean checkout

Requires Docker Compose v2.

```bash
docker compose up --build
```

That single command seeds synthetic source data, initializes the warehouse, runs the first sync, applies conservative duplicate resolution, demonstrates an idempotent rerun, applies insert/update/delete changes, injects and recovers from a mid-run failure, intentionally corrupts a warehouse row, proves the check fails, repairs the table, and runs checks again. Expected final line: `QUALITY CHECK: PASS`.

The SQLite and DuckDB files are persisted under `./data/`. To reset the demo completely, stop containers and remove `data/source.db` and `data/warehouse.duckdb`, then run `docker compose up --build` again. Do not delete these files while the container is running.

Optional commands after the initial demo:

```bash
docker compose run --rm pipeline python -m pipeline.main check
```

This reports row counts plus missing/stale primary keys. A nonzero exit code indicates a mismatch. The demo itself includes a deliberately broken check; the final repair leaves the local warehouse clean.

## Design at a glance

- `source.db`: synthetic operational tables and an append-only `change_log` populated by the demo and mutation helpers.
- `warehouse.duckdb`: warehouse tables, per-table sequence checkpoints, and a customer identity map.
- The sync processes log events in sequence and commits table mutations and checkpoints in one DuckDB transaction. A failed transaction rolls back both data and checkpoints; replay is safe.
- The sample is intentionally small. It demonstrates mechanics, not production throughput.

## Tables seeded

`customers`, `advances`, `transactions`, `cards`, `customer_history` (append-only versions), and `scratch_import` (intentionally excluded). `customers.external_customer_id` is `TEXT`, a deliberately weak schema choice that would be better as a constrained, normalized external identifier with a documented uniqueness policy.

## Limitations

This is a compact demonstrator, not a production CDC connector. SQLite does not reproduce SQL Server CDC/Change Tracking semantics, and DuckDB is not BigQuery. The demo logs changes explicitly rather than installing database triggers for every arbitrary writer. A production version must capture deletes from every write path, persist checkpoints durably, add schema evolution handling, and enforce identity constraints in the source transaction boundary. See [SOLUTION.md](SOLUTION.md).
