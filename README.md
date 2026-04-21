<p align="center">
  <img src="assets/stack_lab.svg" width="200" height="200" alt="StackLab logo" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/stack_lab/actions/workflows/ci.yml">
    <img alt="GitHub Actions Workflow Status" src="https://github.com/nshkrdotcom/stack_lab/actions/workflows/ci.yml/badge.svg" />
  </a>
  <a href="https://github.com/nshkrdotcom/stack_lab/blob/main/LICENSE">
    <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-0b0f14.svg" />
  </a>
</p>

# StackLab

StackLab is the proving harness monorepo for the current platform buildout.

It exists to make single-node boot, multi-node boot, fault injection, restart
drills, and end-to-end examples repeatable from one workspace root.

The current proving set covers the active lower seam, the substrate dispatch
owner, and the product-facing northbound surfaces:

- `examples/single_node_roundtrip`
- `examples/lower_facts_roundtrip`
- `examples/outer_brain_restart_durability`
- `examples/mezzanine_restart_recovery`
- `examples/governed_run_roundtrip`
- `examples/semantic_host_roundtrip`
- `examples/typed_host_roundtrip`
- `examples/multi_node_roundtrip`
- `examples/restart_authority_drill`
- `examples/pressure_failover_drill`

Those examples exercise real `citadel` and real `jido_integration` code
through the harness-only `support/citadel_spine_harness` package. The typed
host proof also assembles real `app_kit` and `citadel_domain_surface` above
the same lower seam. The dedicated OuterBrain restart-durability proof uses
real `outer_brain` persistence, runtime, and restart-authority packages
against backing Postgres. The semantic host proof remains adapter-shaped today
and does not claim that its own path runs through a real `outer_brain`
semantic-runtime surface inside `stack_lab`. The neutral mezzanine restart
recovery proof uses the real execution ledger, JobOutbox-backed dispatch
worker, and runtime-scheduler recovery slice against backing Postgres. The
governed-run proof exercises the current `app_kit -> mezzanine -> citadel ->
jido_integration` control path without product-specific `extravaganza` code.
For substrate-origin commands, that proof uses the Mezzanine substrate ingress
facade and Citadel governance library directly, with a packet reconciliation
gate proving the active path does not use host ingress or host-session
continuity.
The current lower-backed read proofs require tenant-scoped lower facts and
caller-carried lease authorization scope across the `app_kit -> mezzanine ->
jido_integration` path, including negative checks for cross-tenant read and
stream attachment reuse.
Phase 5 adds Scenario 201 for Mezzanine Temporal/Postgres projection drift:
the harness proves compact Temporal describe/query evidence, workflow-start
outbox retirement posture, dispatch-state reduction, and fanout/fanin close
semantics without exporting raw workflow history.
Phase 3 adds product-boundary release proofs: Scenario 31 runs the AppKit
product no-bypass scanner against `extravaganza`, Scenario 36 separately proves
there is no direct Execution Plane bypass in product/AppKit paths, and Scenario
42 proves a second synthetic connector-automation product shape through the
same AppKit northbound boundary.
Phase 3 also adds the M6 release-readiness proofs: Scenario 38 reconstructs
unified traces from all required hot and archived pivots, Scenario 39 rejects
stale installation revisions under lease activation, Scenario 40 exercises
LifecycleContinuation retry/dead-letter/operator recovery, Scenario 41 proves
archival plus archived-trace lookup, and Scenario 43 proves duplicate-safe
lease and worker fencing behavior.
Scenario 34 proves the internal/operator extension authoring path: a valid
signed bundle activates through Mezzanine config registry and invalid bundle
schema, lifecycle hint, policy ref, platform migration, checksum, signature,
and stale revision cases all fail before runtime activation.
Scenario 35 proves operational runbook drift cannot close silently: the harness
checks that every Phase-3 scenario 29-43 names an indexed runbook filename,
that every indexed runbook exists, and that no required runbook remains in
placeholder `[DESIGNED]` state.
The OuterBrain restart-durability proof also carries Phase-3 semantic gateway
coverage: provider-neutral semantic failure carriers are journaled durably,
context adapter requests stay read-only and provenance-preserving, and restart
replay is deduped by reply-publication key.

## Scope

- local harness tooling
- distributed-development runbooks
- fault injection scripts
- support packages and example projects
- end-to-end smoke and drill paths

## Development

```bash
mix deps.get
mix ci
```

Proof scenarios must not mutate committed fixtures or leave generated archive
bundles in tracked paths. Harnesses use OS temp roots or ignored generated
directories so a successful `mix ci` also preserves worktree hygiene.

The harness consumes `AppKit.Boundary.NoBypass` directly for product-boundary
packet reconciliation. Product no-bypass and Execution Plane hazmat no-bypass
are separate checks and both must stay green before release-readiness claims are
accepted.
Runbook drift is also executable: `CitadelSpineHarness.exercise_packet_reconciliation(:phase3_runbook_drift)`
must stay green before any Phase-3 release-readiness closeout.

The welded `stack_lab_lab_core` artifact is tracked through the prepared bundle
flow:

```bash
mix release.prepare
mix release.track
mix release.archive
```

`mix release.track` updates the orphan-backed `projection/stack_lab_lab_core`
branch so downstream repos can pin a real generated-source ref before any
formal release boundary exists.

## Runbook

```bash
just up-single
just up-multi
just fault net-cut
```

## Documentation

- [docs/overview.md](./docs/overview.md)
- [docs/development.md](./docs/development.md)
- [docs/layout.md](./docs/layout.md)
- [docs/runbooks/up_single.md](./docs/runbooks/up_single.md)
- [docs/runbooks/up_multi.md](./docs/runbooks/up_multi.md)
- [docs/runbooks/faults.md](./docs/runbooks/faults.md)
- [support/citadel_spine_harness/README.md](./support/citadel_spine_harness/README.md)

## License

MIT.

Copyright (c) 2026 nshkrdotcom.

## Temporal developer environment

Temporal CLI is expected to be available as `temporal` on this developer workstation for local durable-workflow development. Current provisioning is machine-level dotfiles setup, not a repo-local dependency.

TODO: make Temporal ergonomics explicit for developers by adding repo-local setup scripts, version expectations, and fallback instructions so the tool is not silently assumed from the workstation.

## Native Temporal development substrate

Temporal runtime development is managed from `/home/home/p/g/n/mezzanine` through the repo-owned `just` workflow, not by manually starting ad hoc Temporal processes.

Use:

```bash
cd /home/home/p/g/n/mezzanine
just dev-up
just dev-status
just dev-logs
just temporal-ui
```

Expected local contract: `127.0.0.1:7233`, UI `http://127.0.0.1:8233`, namespace `default`, native service `mezzanine-temporal-dev.service`, persistent state `~/.local/share/temporal/dev-server.db`.
