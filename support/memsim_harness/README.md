# StackLab Memsim Harness

`stack_lab_memsim_harness` owns Phase 7 memory-substrate simulations that
compose owner-repo evidence without claiming release evidence on their own.

The M7A surface starts with Scenario 700,
`multi_node_epoch_monotonicity_and_ordering`. It models two memory-writer
nodes, a StackLab probe, a Postgres truth-store lifecycle, cluster invalidation
observations, per-node AITrace receipts, proof tokens, database row references,
and local-only toxiproxy hooks.
