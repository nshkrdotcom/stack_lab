# Monorepo Project Map

- `./examples/governed_run_roundtrip/mix.exs`: Governed-run proving example for StackLab
- `./examples/lower_facts_roundtrip/mix.exs`: Substrate-facing lower-facts proving example for StackLab
- `./examples/mezzanine_restart_recovery/mix.exs`: Stage-2 restart-recovery proof for the neutral Mezzanine substrate
- `./examples/multi_node_roundtrip/mix.exs`: Multi-node proving example for StackLab
- `./examples/outer_brain_restart_durability/mix.exs`: Stage-1 durable restart-authority proof for OuterBrain
- `./examples/pressure_failover_drill/mix.exs`: Pressure and failover proving example for StackLab
- `./examples/restart_authority_drill/mix.exs`: Restart-authority proving example for StackLab
- `./examples/semantic_host_roundtrip/mix.exs`: Semantic host proving example above the lower seam
- `./examples/session_lineage_drill/mix.exs`: Session-lineage proving example for StackLab
- `./examples/single_node_roundtrip/mix.exs`: Single-node proving example for StackLab
- `./examples/typed_host_roundtrip/mix.exs`: Typed host proving example for AppKit and Citadel.DomainSurface
- `./mix.exs`: Tooling root for the StackLab non-umbrella monorepo
- `./support/citadel_spine_harness/mix.exs`: Harness-only assembly package for Citadel and Jido Integration proofs
- `./support/lab_core/mix.exs`: Shared harness helpers for the StackLab workspace
- `./support/memsim_harness/mix.exs`: Governed-memory substrate simulation helpers for StackLab

# AGENTS.md

## Onboarding

Read `ONBOARDING.md` first for the repo's one-screen ownership, first command,
and proof path.

## Execution Plane dependency wiring

- `support/citadel_spine_harness` consumes `:execution_plane` from
  `../../../execution_plane/core/execution_plane`.
- The harness may also consume lane/runtime package homes directly, such as
  `../../../execution_plane/runtimes/execution_plane_node`,
  `../../../execution_plane/runtimes/execution_plane_process`, and
  `../../../execution_plane/protocols/execution_plane_http`.
- Do not point `:execution_plane` at the sibling repo root. That root is the
  non-published Blitz workspace project, not the Hex package.

## Temporal developer environment

Temporal CLI is implicitly available on this workstation as `temporal` for local durable-workflow development. Do not make repo code silently depend on that implicit machine state; prefer explicit scripts, documented versions, and README-tracked ergonomics work.

## Native Temporal development substrate

When Temporal runtime behavior is required, use the stack substrate in `/home/home/p/g/n/mezzanine`:

```bash
just dev-up
just dev-status
just dev-logs
just temporal-ui
```

Do not invent raw `temporal server start-dev` commands for normal work. Do not reset local Temporal state unless the user explicitly approves `just temporal-reset-confirm`.

## gn-ten batch review

Use `docs/review/gn_ten_batch_review.md` at every gn-ten batch closeout. The
batch receipt is the review unit; do not substitute raw logs, private command
output, or unredacted traces for a reviewed receipt.

<!-- gn-ten:repo-agent:start repo=stack_lab source_sha=ab276c0640772b73065ab12bf05d77be51f1bb67 -->
# stack_lab Agent Instructions Draft

## Owns

- Full-graph assembled proofs.
- Fault injection.
- Restart drills.
- Local distributed-development harness.
- `gn-ten` workspace manifest and proof matrix.

## Does Not Own

- Production business logic.
- Runtime service ownership.
- Product UX.
- Lower execution implementation.

## Allowed Dependencies

- All ranked repos through explicit path dependencies in harness packages.
- AITrace for proof evidence.

## Forbidden Imports

- Harness helpers must not become production APIs.
- Proof support packages must not be consumed by product runtime code.

## Verification

- `mix ci`
- `mix gn_ten.validate`
- Scenario-specific harness tests.

## Escalation

If a proof requires new product/platform behavior, implement that behavior in
the owner repo first, then return to StackLab for assembled proof.
<!-- gn-ten:repo-agent:end -->
