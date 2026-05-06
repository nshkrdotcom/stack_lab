# StackLab Adaptive Control Roundtrip

`stack_lab_adaptive_control_roundtrip` proves a deterministic closed loop from
TRINITY trace refs to eval and replay dataset refs, GEPA candidate target refs,
shadow/canary/approval gates, promotion, rollback, and stale artifact
rejection without live provider dependencies.

Phase 14 adds deterministic adapter proof refs for live-provider gating,
Pristine OpenAPI admission, Prismatic GraphQL admission, explicit durable
persistence preflight, and redacted debug sidecar capture. The example remains
provider-free by default and records missing live disposable credential inputs
as release evidence rather than making network calls.
