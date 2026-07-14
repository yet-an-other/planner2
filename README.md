# Planner

Planner is a personal planning product whose first delivery stack is a calendar-focused web experience.

## Repository

- [`product/`](product/) — platform-neutral Planning language
- [`web/`](web/) — self-contained web UI, supporting server, contracts, deployment, and documentation
- [`CONTEXT-MAP.md`](CONTEXT-MAP.md) — domain contexts and their relationships
- [`docs/adr/`](docs/adr/) — decisions that affect more than one context

Delivery stacks build and release independently. The repository root intentionally has no platform-specific build toolchain.

## Web development

See [`web/README.md`](web/README.md) for setup, local development, tests, and deployment.
