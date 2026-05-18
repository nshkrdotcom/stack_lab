# Agent-Turn Runtime Patterns Receipt

Schema: `gn_ten_agent_turn_runtime_patterns_v1`

Proof: `agent_turn_runtime_patterns`

Profile: `assembled_offline`

Named proof: `proof://stack-lab/agent-turn-runtime-patterns/session-lineage-drill/v1`

Receipt: `receipt://stack_lab/agent_turn_runtime_patterns/latest`

Trace: `trace://stack-lab/agent-turn-runtime-patterns/demo`

Replay: `replay://stack-lab/agent-turn-runtime-patterns/demo`

## Proves

- Multi-turn session recovery preserves the first turn as the source for the
  second turn.
- Dynamic tool manifest `jido://tool-manifest/session-lineage/v2` is resolved
  after recovery and unauthorized tools fail closed.
- Fault injection `primary_lane_timeout` selects the governed Execution Plane
  fallback lane.
- The proof carries repo evidence for OuterBrain, Citadel, Jido Integration,
  Execution Plane, Mezzanine, and AITrace.
- AITrace lineage includes turn start, semantic context restore, dynamic
  manifest resolution, authority check, lower invocation, fallback selection,
  operation receipt, and replay export events.

## Does Not Prove

- live provider behavior
- production multi-node runtime behavior
- real dynamic tool registry mutation
- production AITrace retention policy
