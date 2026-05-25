# gn-ten Node Lab Preflight Receipt

Receipt ref:

```text
receipt://stack_lab/gn_ten_node_lab_preflight/latest
```

Command:

```bash
mix stack_lab.gn_ten.node_lab.preflight \
  --receipt docs/receipts/gn_ten_distributed/node_lab_preflight.json \
  --json
```

Status: pass.

This receipt records the Phase 3 package-owned preflight for
`support/gn_ten_node_lab`. It proves the generic support package can start
EPMD, start a shortname controller node, generate a redacted local-dev cookie
posture, start a peer with `:peer.start_link/1`, synchronize code paths, call
the peer with bounded `:erpc.call/5`, stop the peer, and verify cleanup.

This receipt does not prove owner facade availability, domain business
semantics, monolith/distributed parity, production distribution security, or
release artifact boot.
