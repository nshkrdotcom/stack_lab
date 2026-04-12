# Multi Node Roundtrip

Real split-node assembled proof for `citadel -> jido_integration`.

Covered cases:

- remote durable acceptance
- remote typed scope rejection

This example keeps Citadel local and moves the Spine acceptance path to a peer
node through the harness-owned remote transport.
