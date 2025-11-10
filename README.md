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

## Continuous Integration

- protect `main` branch and submit PR via branch after each ticket