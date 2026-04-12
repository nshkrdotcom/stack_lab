# Single Node Roundtrip

Real same-node assembled proof for `citadel -> jido_integration`.

Covered cases:

- durable acceptance
- typed scope rejection
- duplicate submission convergence

This example boots a real local Citadel runtime and drives a real
`Jido.Integration.V2.BrainIngress` acceptance path through the harness-owned
in-process transport.
