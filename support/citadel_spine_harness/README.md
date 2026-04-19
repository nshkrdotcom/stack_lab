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
- the real `mezzanine` restart-recovery proof through the JobOutbox-backed
  dispatch worker
- the governed-run proof above the `app_kit` operational surface
- the Scenario-19 observability, archived-read honesty, and trace-join
  continuity proof across the public northbound and lower-backed surfaces
- the Scenario-25 AITrace, claim-check, and lower-lineage continuity proof
- the Stage-7 packet-reconciliation and no-bypass boundary proof
- the Phase-3 AppKit-owned product no-bypass and direct Execution Plane
  no-bypass scanner proofs
- the Scenario-42 second product shape proof for connector automation
- the Phase-3 substrate-origin no-session absence proof for the active
  lower-backed AppKit operational path
- the real split-node remote transport proof
- restart and failover drill helpers

It does not move ownership out of the owner repos. Citadel stays the Brain-side
owner, `jido_integration` stays the lower acceptance owner, `mezzanine` stays
the substrate-truth owner, `outer_brain` stays the semantic-runtime owner, and
this package only assembles them for proof work inside `stack_lab`.

The semantic host path in this harness is intentionally adapter-shaped. The
real `outer_brain` durability proof is covered separately by the dedicated
restart-durability scenario.

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

## Generated Artifact Hygiene

The harness must not write mutable proof artifacts into tracked repo paths.
Archival cold-store output is configured under
`System.tmp_dir!/stack_lab_citadel_spine_harness_archival_store`, and scenario
helpers that need isolated cold-store bundles allocate their own OS temp roots.

Committed fixtures are deterministic inputs only. Runtime output belongs in
temp storage or an ignored generated directory that leaves `git status` clean
after `mix ci`.
