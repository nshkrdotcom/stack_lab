# Shared Library + Governed Adapter Review

Use this review pattern when one repo owns a shared library contract and another
repo owns a governed adapter for that contract.

The current reference shape is:

```text
inference
  -> produces shared Inference.Client / Inference.Request / Inference.Response
jido_integration
  -> consumes :inference
  -> owns the governed Inference.Adapter implementation
  -> translates into durable Jido control-plane inference truth
trinity_coordinator, GEPA, products
  -> consume the shared contract
```

## Required Roles

- Shared producer repo is named.
- Governed adapter owner repo is named.
- Downstream consumer repos are named.
- StackLab proof owner is named when an assembled receipt is claimed.

## Shared Producer Checks

- Shared request/response semantics are documented.
- Adapter-specific options are explicitly documented.
- `Client.defaults` and `Request.options` precedence is tested.
- Provider-reported usage, cost, finish reason, object output, and tool calls
  are propagated when available.
- Internal compatibility options do not leak into provider/runtime option bags
  unless documented.
- Producer repo quality gate is green.

## Governed Adapter Checks

- Adapter is owned in the governed repo, not in the shared package.
- Adapter translates the shared request into the governed request/command
  contract.
- Adapter preserves shared defaults, request options, metadata, trace context,
  session, tool policy, and target preference where accepted.
- Request-level values override client defaults where both are accepted.
- Adapter returns durable run and attempt ids, route metadata, usage/cost, and
  finish reason without exposing raw provider payloads or secrets.
- Governed adapter owner quality gate is green.

## Receipt Fields

Record these fields in the batch receipt or closeout note:

```yaml
shared_contract:
  producer_repo: inference
  producer_sha: <pushed sha>
  producer_gate: mix deps.get && mix format --check-formatted && mix compile --warnings-as-errors && mix test && mix credo --strict && mix dialyzer && mix docs
governed_adapter:
  owner_repo: jido_integration
  owner_sha: <pushed sha>
  owner_gate: mix ci
  adapter_module: Jido.Integration.V2.ControlPlane.Inference.Adapter
consumers:
  - trinity_coordinator
  - gepa_ex
proof_limits:
  - does not prove live-provider behavior unless a gated smoke receipt is attached
  - does not prove production deployment
  - does not prove audit truth; traces are evidence only
```

## Public Hygiene

- No raw prompts.
- No provider payloads.
- No API keys, bearer tokens, or secret-shaped fields.
- No workflow histories.
- No private memory or audit content.

## Closeout

- Producer repo is on `main`, pushed, and clean.
- Governed adapter repo is on `main`, pushed, and clean.
- Consumer repos touched by the change are on `main`, pushed, and clean.
- StackLab receipt or review summary distinguishes implemented proof from
  partial proof and names the limits above.

