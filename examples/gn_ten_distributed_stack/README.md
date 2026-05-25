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

Phase 12 adds persistence and external-substrate posture:

- include the existing deterministic persistence matrix proof in distributed
  receipts;
- require `:mickey_mouse` and `:memory_debug` profile facts before a receipt is
  `pass`;
- record Postgres and Temporal as opt-in external profiles only;
- do not start Postgres, Temporal, or Toxiproxy from this proof app.

Phase 13 adds monolith/distributed semantic parity:

- run the fugu router/model roundtrip and the distributed router/model proof
  from one command;
- compare only deterministic semantic fields and ignore placement, timing, and
  transport-attempt evidence;
- hash parity inputs with `GroundPlane.Boundary.Codec`, never `inspect/1`,
  `:erlang.term_to_binary/1`, or direct `Jason.encode!/1`;
- record a parity receipt with deterministic fixture controls and diff
  findings.

Phase 14 adds local scale posture:

- boot a 12-node local topology as the default scale gate;
- keep 32-node and 49-node profiles opt-in;
- block the 49-node stress profile until an explicit host-feasibility receipt
  is supplied;
- record startup duration, resource summary, scheduler flags, peer failures,
  and cleanup status.

## Commands

```bash
mix stack_lab.gn_ten.distributed.prove --profile context_6_node --json
mix stack_lab.gn_ten.distributed.prove --profile router_model_6_node --json
mix stack_lab.gn_ten.distributed.prove --profile parity --json
mix stack_lab.gn_ten.distributed.prove --profile scale_12_node --max-nodes 12 --json
mix stack_lab.gn_ten.distributed.prove --profile partition_recovery --json
```

## QC

```bash
mix format --check-formatted
mix test
```
