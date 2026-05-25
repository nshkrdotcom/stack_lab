# gn-ten Distributed Topology Freeze Receipt

Receipt ref:

```text
receipt://stack_lab/gn_ten_distributed_topology_freeze/latest
```

Command:

```bash
mix gn_ten.topology.freeze --receipt docs/receipts/gn_ten_distributed/topology_freeze.json --json
```

Status: pass.

This receipt freezes the v2 topology vocabulary before the generic node lab
package exists. It proves that StackLab has a reviewed catalog of topology
refs, owner repos, owner-defined discovery groups, node caps, and required
profiles for:

- `control_3_node`
- `context_6_node`
- `full_9_node`
- `partition_recovery`
- `scale_12_node`
- `scale_32_node`
- `scale_49_node`

It also proves the validator rejects unknown owner repos, duplicate node ids,
missing required domains, owner group mismatch, and node counts above cap.

It does not prove EPMD startup, peer lifecycle, owner facade availability,
distributed business semantics, monolith/distributed parity, or 49-node scale
feasibility.
