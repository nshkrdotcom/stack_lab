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

## Commands

```bash
mix stack_lab.gn_ten.distributed.prove --profile context_6_node --json
mix stack_lab.gn_ten.distributed.prove --profile router_model_6_node --json
```

## QC

```bash
mix format --check-formatted
mix test
```
