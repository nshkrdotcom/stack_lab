# Semantic Host Roundtrip

Canonical assembled proof for the semantic northbound path:

`AppKit -> OuterBrain -> Jido.Domain -> Citadel -> Jido.Integration`

This package stays harness-only. It exists to prove the real path above the
owner repos without moving truth into `stack_lab`.

Covered cases:

- semantic turn acceptance through the real AppKit and OuterBrain path
- semantic replay convergence at the Citadel host-ingress seam
- lower-scope rejection read back through Citadel after semantic submission
