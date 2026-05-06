# StackLab Adaptive Control Scanner

`stack_lab_adaptive_control_scanner` verifies closed-loop adaptation facts:
TRINITY trace refs, eval and replay dataset refs, GEPA target refs, candidate
refs, shadow and canary gate refs, approval refs, promotion and rollback refs,
stale artifact rejection refs, AppKit projection refs, and redacted receipts.

Phase 14 extends the same scanner with optional provider-adapter fact groups
for `AOC-045`, `AOC-046`, `AOC-047`, `PERSIST-AOC-006`, and
`PERSIST-AOC-007`. Those facts prove live-provider gates stay blocked until
deterministic GEPA, TRINITY, and adaptive-control proofs are green; Pristine
OpenAPI operations carry governed admission refs; Prismatic GraphQL operations
bind operation, provider account, workspace, token family, tenant, and subject;
durable persistence profiles fail closed without substrate and migration refs;
and debug sidecar receipts contain only redacted refs, summaries, states,
hashes, and receipts.
