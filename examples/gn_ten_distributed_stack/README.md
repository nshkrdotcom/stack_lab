# StackLab Gn-Ten Distributed Stack

`examples/gn_ten_distributed_stack` is the local distributed proof app for the
gn-ten stack.

Phase 8 owns the first context proof:

- run the fugu single-node Context ABI roundtrip as the monolith baseline;
- boot a local peer-mode context topology with StackLab node lab;
- verify owner facade modules register owner-defined groups on distinct peers;
- scan distributed proof envelopes before accepting the receipt;
- record that this is a local Erlang distribution proof, not production
  security or release packaging proof.

Phase 9 extends the proof through the fugu router/model substrate:

- run the fugu single-node router fabric roundtrip as the monolith baseline;
- boot AppKit, Mezzanine, Citadel, OuterBrain, Jido Integration, and AITrace
  profile nodes;
- prove route decision refs, model invocation receipts, token/cost summaries,
  and stream-fragment posture stay bounded and ref-shaped;
- keep Execution Plane lower-lane execution out of the default proof until a
  scenario requires it.

Phase 11 records local fault and recovery posture:

- emit bounded fault receipts for node crash, distribution disconnect/heal,
  facade timeout, stale DTO, duplicate delivery, and trace exporter failure;
- cite owner recovery evidence for Mezzanine, Citadel, StackLab's existing
  pressure/failover drill, and AITrace;
- keep WAN, production discovery, release boot, and live-provider retry
  semantics as explicit non-claims.

## Commands

```bash
mix stack_lab.gn_ten.distributed.prove --profile context_6_node --json
mix stack_lab.gn_ten.distributed.prove --profile router_model_6_node --json
mix stack_lab.gn_ten.distributed.prove --profile partition_recovery --json
```

## QC

```bash
mix format --check-formatted
mix test
```
