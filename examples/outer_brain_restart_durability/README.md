# OuterBrain Restart Durability

Real Stage-1 durability proof for `outer_brain`.

Covered cases:

- restart-critical semantic truth survives process restart
- restart authority reconstructs from durable tables instead of in-memory-only
  journal state

This example uses the real `outer_brain` persistence, runtime, and restart
authority packages against a backing Postgres container inside `stack_lab`.
