# StackLab Synapse Product Acceptance

This proof app exercises the rebuilt Synapse product from outside the product
repo. It depends on `synapse_core` and StackLab's product no-bypass scanner, then
calls Synapse's product-facing modules instead of reimplementing Synapse
behavior in the harness.

Run it directly:

```sh
cd /home/home/p/g/n/stack_lab/examples/synapse_product_acceptance
MIX_ENV=test mix stack_lab.proof_app.synapse.acceptance --json
```

Run it through the StackLab root command:

```sh
cd /home/home/p/g/n/stack_lab
MIX_ENV=test mix stack_lab.synapse.acceptance --json
```

The receipt proves fixture-backed bootstrap, run start, turn submission, review
decision, memory/context projection, denial posture, evidence projection, and
source-level product no-bypass signals. Cross-tenant rejection is recorded as
not applicable while Synapse remains a single-tenant fixture product with no
live persisted tenant data surface.
