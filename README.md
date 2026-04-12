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

StackLab is a starter harness for local distributed development around the nshkr infrastructure stack.

The repository is intentionally simple for now. It exists to hold the first repeatable shape for single-node boot, multi-node boot, fault injection, and end-to-end proving examples while the broader process is still being defined.

## Scope

- local stack boot
- multi-node development flows
- fault injection and recovery drills
- end-to-end proving examples
- operator-oriented smoke paths

## Status

Early starter repository. The exact workflow, example inventory, and service graph are still being nailed down.

## Development

The project targets Elixir `~> 1.19` and Erlang/OTP `28`. The pinned toolchain lives in [`.tool-versions`](./.tool-versions).

```bash
mix deps.get
mix test
```

## Documentation

- [docs/overview.md](./docs/overview.md)
- [docs/development.md](./docs/development.md)
- [docs/layout.md](./docs/layout.md)
- [CHANGELOG.md](./CHANGELOG.md)

## License

MIT. See [LICENSE](./LICENSE).
