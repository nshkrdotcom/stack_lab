# Semantic Host Roundtrip

Canonical assembled proof for the semantic northbound path:

`AppKit -> semantic host surface -> Citadel.DomainSurface -> Citadel -> Jido.Integration`

This package stays harness-only. It exists to prove the real path above the
owner repos without moving truth into `stack_lab`.

Covered cases:

- semantic turn acceptance through the real AppKit semantic host path
- semantic replay convergence at the Citadel host-ingress seam
- lower-scope rejection read back through Citadel after semantic submission

This package does not yet prove a real `outer_brain` durability runtime.
