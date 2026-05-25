# Distributed Cleanup Runbook

Use this runbook after local distributed StackLab proofs, especially after a
failed run or interrupted terminal session.

## Normal Cleanup

```bash
mix stack_lab.gn_ten.node_lab.down --json
```

The command removes the node-lab run-state file. Peer-mode proofs also stop
peers before the original command returns and record cleanup receipts.

## Verify EPMD State

```bash
epmd -names
```

No expected `stack_lab` proof node should remain after cleanup. If a local
debug session is still attached, close it before treating the cleanup as
complete.

## Inspect Status

```bash
mix stack_lab.gn_ten.node_lab.status --json
```

A clean state reports `no_active_run`. If a run state remains, inspect the
status summary for log paths, cleanup posture, and node ids, then rerun
`down`.

## Worktree Hygiene

```bash
git status --short
```

Generated runtime output belongs under ignored or temporary paths. A proof run
must not create tracked source, fixture, or docs changes unless the phase
explicitly updates deterministic fixtures or proof-matrix rows.
