# Distributed Debugging

StackLab distributed debugging is a local proof-harness workflow. It helps
inspect peer-mode runs without turning Erlang distribution into a production
security model or a platform business API.

## Status

```bash
mix stack_lab.gn_ten.node_lab.status --json
```

The status receipt reports:

- run id and topology ref;
- logical node id, profile, and BEAM node name;
- started OTP apps;
- owner-defined `:pg` membership;
- facade readiness;
- current connection posture;
- log path;
- latest receipt refs;
- cleanup posture;
- artifact hygiene for run-state and log paths.

It must not include Erlang cookie values. The word `cookie` may appear in
posture fields, but the secret value is never printed.

## Attach

```bash
mix stack_lab.gn_ten.node_lab.attach --node mezzanine_workflow_0 --json
```

The attach command prints a redacted local shell recipe for the selected
logical node:

```text
iex --sname debug_shell_<run> --cookie <redacted_run_cookie> --remsh <node>
```

This is a development convenience. It is not tenant authority, not product
authority, and not a production operations model. Current peer-mode runs clean
up peers before returning, so attach receipts can be `not_attached` while still
documenting the safe recipe and node target.

## Logs

Node-lab logs are written under generated or temporary paths such as:

```text
tmp/stack_lab/<run_id>/logs/distributed.log
```

Each line includes timestamp, profile, logical node id, BEAM node name, stream,
correlation ref, and a redacted message. Cookies, credentials, raw prompts, raw
memory, and raw provider payloads are not valid log output.

## Local Inspection

Observer and low-level Erlang tracing are local-only debugging aids:

```elixir
:observer.start()
```

Automated proof assertions use owner receipts, StackLab receipts, and AITrace
exports. They do not depend on Observer, remote PIDs, or ad hoc `:dbg` output.
