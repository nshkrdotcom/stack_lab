# Session Lineage Drill

Deterministic assembled proof for `agent_turn_runtime_patterns`.

The proof is provider-free and exercises the runtime facts required for a
multi-turn agent session:

- semantic context and recovery refs from OuterBrain;
- authority decisions from Citadel;
- dynamic tool manifest refs from Jido Integration;
- primary and fallback lower lane refs from Execution Plane;
- workflow checkpoint and receipt refs from Mezzanine;
- AITrace lineage event and replay refs.

Run it with:

```bash
mix test
```

Receipt summary:

```text
docs/receipts/agent_turn_runtime_patterns.md
```
