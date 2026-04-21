# Citadel Spine Harness

Harness-only support package for assembled substrate and northbound proof work
in `stack_lab`.

This package owns:

- sibling repo resolution for `stack_lab`, `app_kit`, `extravaganza`,
  `execution_plane`, `citadel`, `jido_integration`, `mezzanine`, `outer_brain`,
  and the authoritative packet docs
- the real same-node in-process transport proof
- the real substrate-facing lower-facts readback proof
- the real `outer_brain` restart-durability proof
- the Phase-3 Outer Brain semantic-failure carrier, durable journal, and
  duplicate-publication suppression proofs
- the real `mezzanine` restart-recovery proof through the JobOutbox-backed
  dispatch worker
- the governed-run proof above the `app_kit` operational surface
- the Scenario-19 observability, archived-read honesty, and trace-join
  continuity proof across the public northbound and lower-backed surfaces
- the Scenario-38 and Scenario-41 archived unified-trace reconstruction proof
  across trace, subject, execution, decision, run, attempt, artifact, and
  manifest pivots with phase-3 staleness labels
- the Scenario-39 installation revision and runtime lease proof for
  attempted/current revision diagnostics and mixed-node fail-closed behavior
- the Scenario-40 lifecycle continuation proof for transient retry,
  deterministic dead-letter, operator retry, and operator waive flows
- the Scenario-43 duplicate-safe lease and worker fencing proof for competing
  owners, node-loss takeover, lower-submission idempotency, and startup
  reconciliation dedupe
- the Scenario-34 extension authoring proof for deterministic internal/operator
  bundle import, activation, and pre-runtime rejection gates
- the Scenario-35 runbook drift proof that every Phase-3 release scenario maps
  to an indexed, built operator runbook
- the Scenario-25 AITrace, claim-check, and lower-lineage continuity proof
- the Stage-7 packet-reconciliation and no-bypass boundary proof
- the Phase-3 AppKit-owned product no-bypass and direct Execution Plane
  no-bypass scanner proofs
- the Scenario-42 second product shape proof for connector automation
- the Phase-3 substrate-origin no-session absence proof for the active
  lower-backed AppKit operational path
- the Phase-5 Scenario-201 Temporal/Postgres projection-drift proof for compact
  describe/query evidence, workflow-start outbox retirement posture,
  dispatch-state reduction, and fanout/fanin close semantics
- the real split-node remote transport proof
- restart and failover drill helpers

It does not move ownership out of the owner repos. Citadel stays the Brain-side
owner, `jido_integration` stays the lower acceptance owner, `mezzanine` stays
the substrate-truth owner, `outer_brain` stays the semantic-runtime owner, and
this package only assembles them for proof work inside `stack_lab`.

The semantic host path in this harness is intentionally adapter-shaped. The
real `outer_brain` durability proof is covered separately by the dedicated
restart-durability scenario.

That durability scenario now includes semantic failure carrier replay and
reply-publication dedupe checks. It records `OuterBrain.Contracts.SemanticFailure`
through the durable `OuterBrain.Persistence.Store`, restarts the repo/session
view, reconstructs restart authority, and proves replay cannot create a second
user-visible publication row for the same dedupe key.

The lower-backed AppKit operational proof now enters Citadel through
`Mezzanine.Citadel.SubstrateIngress` and the pure
`Citadel.Governance.SubstrateIngress` compiler. It still submits the resulting
`InvocationRequest.V2` through the real invocation bridge into Jido Integration,
but it does not use `Citadel.HostIngress` or host-session continuity for
substrate-origin commands.

The lower-backed AppKit and lower-facts proofs now also carry tenant-scoped
read authorization end to end. Harness stubs require
`Jido.Integration.V2.TenantScope`, Mezzanine leases require
`Mezzanine.Leasing.AuthorizationScope`, and the scenario assertions prove that
submission receipt, run, attempt, event, artifact, trace, read-lease, and
stream-attach pivots cannot be reused across tenants.

Product-boundary packet reconciliation uses `AppKit.Boundary.NoBypass` from the
sibling AppKit repo instead of local regex-only policy. The `product` profile
checks `extravaganza` product source for lower governed-write imports, and the
`hazmat` profile separately checks AppKit and product paths for direct Execution
Plane usage.

Scenario 34 uses the real `Mezzanine.Authoring.Bundle` and
`MezzanineConfigRegistry.import_authoring_bundle/2` path. It proves a valid
checksum/signature bundle activates and that invalid policy refs, platform
migrations, lifecycle hints, context adapter descriptors, checksum, signature,
and stale installation revision reject before activation.

Scenario 35 uses `PacketReconciliation.run_case(:phase3_runbook_drift)` against
the Phase-3 packet under
`nshkrdotcom/docs/20260418/ecosystem_buildout_phase3`. It verifies the
runbook index, Scenario 29-43 runbook references in `STACK_LAB_SPEC.md`, and
absence of placeholder runbook content.

## Generated Artifact Hygiene

The harness must not write mutable proof artifacts into tracked repo paths.
Archival cold-store output is configured under
`System.tmp_dir!/stack_lab_citadel_spine_harness_archival_store`, and scenario
helpers that need isolated cold-store bundles allocate their own OS temp roots.

Committed fixtures are deterministic inputs only. Runtime output belongs in
temp storage or an ignored generated directory that leaves `git status` clean
after `mix ci`.
