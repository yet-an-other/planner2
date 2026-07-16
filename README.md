# Planner

Planner is a personal planning product.

## Repository

- [`product/`](product/) — platform-neutral Planning language
- [`web/`](web/) — self-contained web UI, supporting server, contracts, deployment, and documentation
- [`ios/`](ios/) — self-contained native iPhone and iPad application, tests, assets, and documentation
- [`CONTEXT-MAP.md`](CONTEXT-MAP.md) — domain contexts and their relationships
- [`docs/adr/`](docs/adr/) — decisions that affect more than one context
- [`AGENTS.md`](AGENTS.md) — repository guidance for coding agents
- [`docs/agents/`](docs/agents/) — domain-documentation and issue-tracker conventions

Delivery stacks build and release independently. The repository root intentionally has no platform-specific build toolchain.

## Web development

See [`web/README.md`](web/README.md) for setup, local development, tests, and deployment.

## iOS development

See [`ios/README.md`](ios/README.md) for Xcode requirements, supported devices, builds, tests, signing behavior, and deliberate scope exclusions.
