# Extravaganza Non-UI Lane

Run the credential-free internal fixture from the harness package:

```bash
cd /home/home/p/g/n/stack_lab/support/citadel_spine_harness
mix test test/extravaganza_non_ui_lane_test.exs
```

The fixture proves product pack compilation, typed AppKit runtime projection
readback, Extravaganza workpad rendering, local worker identity flow, SSH
execution-surface contract coverage, required failure variant mapping, and the
provider smoke command contract.

Run the opt-in provider smoke check from the workspace root. When using
`--linear-api-key-stdin`, pipe the secret into the command or finish stdin
manually with EOF, typically `Ctrl-D`; the task does not read credentials from
process environment.

```bash
cd /home/home/p/g/n/stack_lab
mix stack_lab.provider_smoke_check \
  --linear-api-key-stdin \
  --github-repo nshkrdotcom/test
```

The root task delegates to `support/citadel_spine_harness`, which owns the
implementation. This provider smoke command composes the owner-owned Linear, GitHub,
Codex, and Mezzanine Temporal live surfaces and writes a local receipt under
the OS temp directory unless `--receipt-file path` is supplied. It creates or
discovers provider objects dynamically, preserves the Linear terminal comment
as publication evidence, creates/reviews/closes a disposable GitHub PR, deletes
the disposable branch, runs the Codex app-server proof, and checks/starts
Temporal only through Mezzanine `just` commands. Static provider object
selectors do not satisfy this runbook and are rejected by the command parser.

An interactive `--linear-api-key-stdin` invocation waits until EOF before any
provider smoke work starts. After credential input is complete, the full smoke
check is expected to take minutes because it checks/starts Temporal and performs
real Linear, GitHub, and Codex calls. The command prints safe progress markers
when stdin is consumed and when each live stage starts or finishes; it never
prints credential values.
