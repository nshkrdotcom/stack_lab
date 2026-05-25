# gn-ten Distribution Preflight Receipt

Receipt ref:

```text
receipt://stack_lab/gn_ten_distributed_preflight/latest
```

Command:

```bash
mix gn_ten.distribution.preflight --receipt docs/receipts/gn_ten_distributed/distribution_preflight.json --json
```

Status: pass.

This receipt records the v2 Phase 2 host preflight before
`support/gn_ten_node_lab` exists. It proves that this workstation can:

- find and start EPMD;
- start a StackLab controller node with shortnames;
- generate a redacted per-run cookie value without writing it to receipts;
- validate the planned distribution port range `43000..43100`;
- start a temporary peer node with `:peer.start_link/1`;
- call the peer with bounded `:erpc.call/5`;
- stop the peer and verify it is unreachable after cleanup;
- record current EPMD names and listen-socket exposure with `ss -ltn`;
- keep `examples/multi_node_roundtrip` and `support/citadel_spine_harness`
  parallel in root CI until `support/gn_ten_node_lab` can migrate them.

The receipt intentionally records a local warning:

```text
non_loopback_distribution_socket
```

EPMD and the local distribution listener are not loopback-only on this host.
That is acceptable for the local development proof. Any staging or production
security claim must fail closed until a different distribution/security
topology is implemented and proven.

This receipt does not prove owner facade availability, domain business
semantics, monolith/distributed parity, per-run cookie application to peers,
production distribution security, or release artifact boot.
