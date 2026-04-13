# Typed Host Roundtrip

Real typed-host assembled proof for:

`AppKit -> Jido.Domain -> Citadel -> Jido.Integration`

Covered cases:

- typed command acceptance through the real AppKit and Domain northbound path
- duplicate typed command convergence at the Citadel host-ingress seam
- lower-scope rejection read back through Citadel after typed submission

This example boots a real local Citadel runtime, routes a real `AppKit`
command through `Jido.Domain`, and proves that the resulting Citadel outbox
entry reaches durable Spine acceptance or durable rejection handling.
