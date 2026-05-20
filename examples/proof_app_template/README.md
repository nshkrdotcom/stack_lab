# StackLab Proof App Template

Use this template when adding another proof product under `stack_lab/examples`.
The proof app should be a small Mix project with focused modules and a thin
top-level orchestrator.

## Required Shape

- `ProductHost`: product scenario, required components, role refs, binding
  fixture data, state mapping, output field groups, and forbidden product terms.
- `Pack`: pack manifest and binding declaration fixtures.
- `FoundationProof`: pack compilation, registry activation, manifest lookup,
  authority, credential lease, binding resolution, lower invocation, and receipt
  creation.
- `ReplayProof`: receipt reduction, projection mapping, lineage outbox events,
  and AITrace replay or negative controls.
- Boundary probes: AppKit role-ref surface, Execution Plane dispatch, and any
  product-specific live boundary required by the proof.
- Local deterministic fixture: supervised service or store used by tests.
- Top-level module: public API wrappers and full acceptance composition only.

## Required Checks

- Unit tests for product scenario, pack bindings, shape gates, foundation proof,
  replay proof, boundary probes, fault cases, bypass rejection, and full
  acceptance.
- `mix test` and `mix ci` in the proof app.
- Root StackLab `mix ci` after the proof app is added or changed.
- No provider vocabulary in neutral proof code unless the proof app explicitly
  models a provider boundary.
- No unsupervised production processes. Local fixtures must use supervised
  process ownership in tests.
