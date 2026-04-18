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
