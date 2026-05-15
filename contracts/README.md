# Contracts

This directory is the canonical source of truth for all cross-service interfaces.
No API endpoint or event type may be implemented before its contract is defined here.

## Structure

```
contracts/
├── api/              # REST API definitions — one subdirectory per service
│   └── <service>/
│       └── openapi.yml   # OpenAPI 3.x specification
├── events/           # Async event type schemas — one file per event type
│   └── <event-type>.json # JSON Schema (or .avsc for Avro)
└── capabilities/     # Eureka capability metadata key registry
    └── <key>.md      # Documents a single capability key
```

## Rules

- Every new REST endpoint MUST have a corresponding `contracts/api/<service>/openapi.yml`
  entry **before** the implementation PR is opened.
- Every new Kafka event type MUST have a schema in `contracts/events/` **before** any
  producer or consumer is implemented.
- Every cross-service capability key MUST be registered in `contracts/capabilities/`
  **before** the consuming side checks for it in Eureka metadata.
- Contract files are reviewed as part of the standard PR process; API or event changes
  without a contract update are blocked at code review.
