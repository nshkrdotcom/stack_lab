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

The current assembled lower-stack proof is the Citadel plus Spine durable
submission seam:

- `examples/single_node_roundtrip`
- `examples/semantic_host_roundtrip`
- `examples/typed_host_roundtrip`
- `examples/multi_node_roundtrip`
- `examples/restart_authority_drill`
- `examples/pressure_failover_drill`

Those examples exercise real `citadel` and real `jido_integration` code
through the harness-only `support/citadel_spine_harness` package. The typed
and semantic host proofs also assemble real `app_kit`, `outer_brain`,
and `jido_domain` above the same lower seam.

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
