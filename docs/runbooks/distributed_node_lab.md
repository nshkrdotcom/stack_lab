# Distributed Node Lab Runbook

This runbook covers the Phase 6 local node-lab command surface. It is a
StackLab harness workflow, not a production distribution model.

## Preflight

```bash
mix stack_lab.gn_ten.node_lab.preflight --json
```

The preflight verifies EPMD, local shortname distribution, peer startup,
code-path sync, bounded remote calls, cleanup, and redacted cookie posture.

## Topology Boot

Use the deterministic fixture topology for package-level command checks:

```bash
mix stack_lab.gn_ten.node_lab.up \
  --topology support/gn_ten_node_lab/priv/topologies/fixture_single_node.exs \
  --json
```

The command starts a peer, syncs code paths, boots required apps, hosts the
owner-defined facade group, probes `:pg`, writes a run-state receipt under
`tmp/stack_lab/gn_ten_node_lab/`, and stops the peer before returning.

`--keep` records intent only in Phase 6. It does not claim cross-command peer
retention. That claim belongs to a later daemon or release-path controller.

## Status, Probe, And Cleanup

```bash
mix stack_lab.gn_ten.node_lab.status --json
mix stack_lab.gn_ten.node_lab.probe --node fixture_profile_0 --json
mix stack_lab.gn_ten.node_lab.down --json
```

`status` reads the latest run-state receipt. `probe` reads one logical node
receipt from that state. `down` removes the run-state file and is idempotent.

## Safety Notes

- Receipts do not include Erlang cookie values.
- Peer PIDs are harness observations only, not platform DTOs.
- Owner apps register owner-defined groups such as
  `{Mezzanine.RemoteFacade.Workflow, :workflow}`; StackLab topology maps proof
  profiles to those groups.
- Domain semantics remain in owner repos.
