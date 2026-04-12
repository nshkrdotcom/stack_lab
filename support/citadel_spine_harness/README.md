# Citadel Spine Harness

Harness-only support package for assembled `citadel -> jido_integration`
proofs in `stack_lab`.

This package owns:

- sibling repo resolution for `stack_lab`, `citadel`, and `jido_integration`
- the real same-node in-process transport proof
- the real split-node remote transport proof
- restart and failover drill helpers

It does not move ownership out of the owner repos. Citadel stays the Brain-side
owner, `jido_integration` stays the Spine-side owner, and this package only
assembles them for proof work inside `stack_lab`.
