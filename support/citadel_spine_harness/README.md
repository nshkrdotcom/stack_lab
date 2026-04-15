# Citadel Spine Harness

Harness-only support package for assembled `citadel -> jido_integration`
proofs in `stack_lab`.

This package owns:

- sibling repo resolution for `stack_lab`, `citadel`, `jido_integration`, and
  `outer_brain`
- the real same-node in-process transport proof
- the real substrate-facing lower-facts readback proof
- the real `outer_brain` restart-durability proof
- the real split-node remote transport proof
- restart and failover drill helpers

It does not move ownership out of the owner repos. Citadel stays the Brain-side
owner, `jido_integration` stays the Spine-side owner, `outer_brain` stays the
semantic-runtime owner, and this package only assembles them for proof work
inside `stack_lab`.

The semantic host path in this harness is intentionally adapter-shaped. The
real `outer_brain` durability proof is covered separately by the dedicated
restart-durability scenario.
