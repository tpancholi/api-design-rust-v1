# API Design with Rust

RAG API using HuggingFace models powered by Rust

## Development commands

- inner development loop
    - it will start by running `cargo check`
    - if it succeeds, `cargo test` would run
    - if test passes, it would launch application with `cargo run`

```
cargo watch -x check -x test -x run
```

## Continuous Integration (GitHub actions)

- general.yml
    - format, lint, test and check code coveraage
- audit.yml
    - weekly run (sunday) to check for vulenerability and other security issues

## Postgres v18 setup for development

Steps to follow:

- make sure the scripts are in executable mode

```
chmod +x ./scripts/init_db.sh ./scripts/stop_postgres.sh
```

- start fresh PostgreSQL 18

```
./scripts/init_db.sh
```

- verify postgres18 setup

```
docker exec -it rust_pg18 psql -U postgres -d habit_tracker_db -c "SELECT uuidv7();"
```

- Stop (and optionally delete data)

```
./scripts/stop_postgres.sh
```

- Post initialization subsequent db start script

```bash
SKIP_DOCKER=true ./scripts/init_db.sh
```

- DB URL -> `postgres://app:secret@localhost:5432/habit_tracker_db`

