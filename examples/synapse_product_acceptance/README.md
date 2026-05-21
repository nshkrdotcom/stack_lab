# StackLab Synapse Product Acceptance

This proof app exercises the rebuilt Synapse product from outside the product
repo. It depends on `synapse_core` and StackLab's product no-bypass scanner, then
calls Synapse's product-facing modules instead of reimplementing Synapse
behavior in the harness.

Run it directly:

```sh
cd /home/home/p/g/n/stack_lab/examples/synapse_product_acceptance
MIX_ENV=test mix stack_lab.proof_app.synapse.acceptance --json
MIX_ENV=test mix stack_lab.proof_app.synapse.live_slice --json
MIX_ENV=test mix stack_lab.proof_app.synapse.staged_live.v1 --json
```

Run it through the StackLab root command:

```sh
cd /home/home/p/g/n/stack_lab
MIX_ENV=test mix stack_lab.synapse.acceptance --json
MIX_ENV=test mix stack_lab.synapse.live_slice --json
MIX_ENV=test mix stack_lab.synapse.staged_live.v1 --json
```

The receipt proves fixture-backed bootstrap, run start, turn submission, review
decision, memory/context projection, denial posture, evidence projection, and
source-level product no-bypass signals. Cross-tenant rejection is recorded as
not applicable while Synapse remains a single-tenant fixture product with no
live persisted tenant data surface.

The staged-live receipt proves the promoted diagnostic path through Synapse
product code, AppKit EffectSurface, Mezzanine governed-effect lifecycle,
Citadel diagnostic authority, Jido diagnostic direct runtime, Execution Plane
diagnostic execution, AITrace governed-effect evidence, and AppKit product-safe
readback. It does not claim live provider behavior.
