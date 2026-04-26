# Extravaganza Non-UI Lane

Run the credential-free internal fixture from the harness package:

```bash
cd /home/home/p/g/n/stack_lab/support/citadel_spine_harness
mix test test/extravaganza_non_ui_lane_test.exs
```

The fixture proves product pack compilation, typed AppKit runtime projection
readback, Extravaganza workpad rendering, local worker identity flow, SSH
execution-surface contract coverage, required failure variant mapping, and the
dynamic live command contract.

Run the opt-in live provider proof from the workspace root. When using
`--linear-api-key-stdin`, pipe the secret into the command or finish stdin
manually; the task does not read credentials from process environment.

```bash
cd /home/home/p/g/n/stack_lab
mix stack_lab.extravaganza.live_e2e \
  --linear-api-key-stdin \
  --github-repo nshkrdotcom/test
```

The root task delegates to `support/citadel_spine_harness`, which owns the
implementation. This live command composes the owner-owned Linear, GitHub,
Codex, and Mezzanine Temporal live surfaces and writes a local receipt under
the OS temp directory unless `--receipt-file path` is supplied. It creates or
discovers provider objects dynamically, preserves the Linear terminal comment
as publication evidence, creates/reviews/closes a disposable GitHub PR, deletes
the disposable branch, runs the Codex app-server proof, and checks/starts
Temporal only through Mezzanine `just` commands. Static provider object
selectors do not satisfy this runbook and are rejected by the command parser.
