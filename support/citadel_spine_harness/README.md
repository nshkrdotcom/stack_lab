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
- the real split-node remote transport proof
- restart and failover drill helpers

It does not move ownership out of the owner repos. Citadel stays the Brain-side
owner, `jido_integration` stays the lower acceptance owner, `mezzanine` stays
the substrate-truth owner, `outer_brain` stays the semantic-runtime owner, and
this package only assembles them for proof work inside `stack_lab`.

The semantic host path in this harness is intentionally adapter-shaped. The
real `outer_brain` durability proof is covered separately by the dedicated
restart-durability scenario.

## Generated Artifact Hygiene

The harness must not write mutable proof artifacts into tracked repo paths.
Archival cold-store output is configured under
`System.tmp_dir!/stack_lab_citadel_spine_harness_archival_store`, and scenario
helpers that need isolated cold-store bundles allocate their own OS temp roots.

Committed fixtures are deterministic inputs only. Runtime output belongs in
temp storage or an ignored generated directory that leaves `git status` clean
after `mix ci`.
