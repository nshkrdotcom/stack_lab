# gn-ten Proof Matrix

Date: 2026-04-28

This matrix maps the `gn-ten` contract docset to executable StackLab proof
ownership. Entries marked `missing-proof` are intentional backlog items, not
claims of completed behavior.

Machine-readable ledger:

```text
proof_matrix.yml
```

The YAML ledger is the source used by `mix gn_ten.proofs.validate`. This
Markdown file remains the human-readable review surface.

Phase E trace joins:

```text
trace://stack_lab/local_quick/latest
```

The local-quick trace joins are development evidence only. They explicitly do
not claim authoritative audit truth or production deployment proof.

## Repository Coverage

| Repo | Repo Ref | Current Proof Posture | Command | Evidence |
| --- | --- | --- | --- | --- |
| `ground_plane` | `repo://nshkrdotcom/ground_plane` | stable primitive contract package plus artifact ledger proof | `mix ci` in `ground_plane` | stable `ground_plane_contracts` artifact |
| `execution_plane` | `repo://nshkrdotcom/execution_plane` | lower lane and node proofs through StackLab | `mix ci` in `execution_plane`; StackLab lower runtime scenarios | lower outcome refs |
| `jido_integration` | `repo://nshkrdotcom/jido_integration` | connector/lower gateway proofs through StackLab | `mix ci` in `jido_integration`; StackLab connector scenarios | review packet and lower receipt refs |
| `citadel` | `repo://nshkrdotcom/citadel` | policy packet and authority proofs through StackLab | `mix ci` in `citadel`; StackLab governance scenarios | authority refs |
| `outer_brain` | `repo://nshkrdotcom/outer_brain` | restart durability and semantic failure proofs | `mix ci` in `outer_brain`; StackLab restart scenarios | semantic failure and journal refs |
| `mezzanine` | `repo://nshkrdotcom/mezzanine` | lifecycle, projection, audit, Temporal/Postgres drift proofs | `mix ci` in `mezzanine`; StackLab projection drift scenarios | projection and incident refs |
| `app_kit` | `repo://nshkrdotcom/app_kit` | product no-bypass and DTO conformance proofs | `mix ci` in `app_kit`; `mix test test/stack_lab/gn_ten_product_no_bypass_test.exs` in `stack_lab` | no-bypass scan receipts and fixture proof |
| `extravaganza` | `repo://nshkrdotcom/extravaganza` | thin product and headless parity proofs | `mix ci` in `extravaganza`; StackLab product lane fixture | AppKit DTO and no-bypass receipt refs |
| `stack_lab` | `repo://nshkrdotcom/stack_lab` | assembled proof owner | `mix ci`; `mix gn_ten.validate` | proof matrix and scenario receipts |
| `AITrace` | `repo://nshkrdotcom/AITrace` | trace export and single-node proof-trace fixture | AITrace equivalent CI gate | `aitrace.single_node_proof_trace.v1` |

## Contract Family Coverage

| Contract Family | Owner | Proof Status | Next Action |
| --- | --- | --- | --- |
| 000 repo contracts | docs + repo owners | documentation complete | copy reviewed repo-agent instructions into repo roots |
| 100 development process | `stack_lab`, `AITrace` | partial source-backed proof | add trace fixtures for local proof loops |
| 200 refactoring | repo owners | missing-proof | link each deletion campaign to a StackLab scenario or no-op proof |
| 300 architecture | docs + `stack_lab` | manifest, artifact ledger, and product no-bypass fixtures implemented | keep product fixture proof wired into CI and expand fixtures as product shapes change |
| 400 agent patterns | `outer_brain`, `citadel`, `jido_integration`, `execution_plane` | partial source-backed proof | add dynamic tool manifest and session proof rows |
| 500 governance | `citadel`, `mezzanine`, `jido_integration` | tenant isolation scenarios implemented; compliance export remains partial | add incident/compliance export fixtures |
| 600 deployment | `stack_lab`, `mezzanine`, `AITrace` | local single-node deployment rehearsal implemented | convert local rehearsals into clean-host operator drills once deploy scripts are repo-owned |

## Release Readiness Proof Profiles

| Profile | Scope | Required Evidence |
| --- | --- | --- |
| `local_quick` | manifest, repo refs, proof matrix, no-bypass scans | `mix gn_ten.validate`, focused repo tests |
| `local_full` | all repo-local CI gates in manifest order | command receipts and clean worktrees |
| `assembled_offline` | StackLab fixture-backed full graph | StackLab scenario receipts and AITrace fixture |
| `deployment_single_node` | single-node production rehearsal | deployment receipt, backup/restore receipt, trace export |

## Implemented Fixture Proofs

- `product_no_bypass`: runs the AppKit-owned scanner against StackLab-owned
  fixtures in `fixtures/products/`. The minimal fixture imports only product-safe AppKit
  surfaces. The hostile fixture imports direct bridge/lower-layer modules and
  must fail before a product can bypass AppKit.
- `single_node_deployment_rehearsal`: validates five separate Phase J local
  deployment rehearsal receipts under `docs/receipts/gn_ten_deployment/`:
  cold deploy, backup/restore, substrate health, zero-downtime migration, and
  websocket reconnect. Each receipt carries
  `production_deployment_proven?: false`.
- `tenant_isolation_read`: runs the provider-free StackLab tenant scenario that
  proves a tenant A read cannot see the tenant B fixture record.
- `tenant_isolation_write`: runs the provider-free StackLab tenant scenario that
  proves a tenant A write cannot mutate a tenant B fixture record.
- `tenant_lease_handling`: runs the provider-free StackLab tenant scenario that
  proves a tenant A lease cannot be used by tenant B, and pairs with
  `mix gn_ten.tenant.scan --root /home/home/p/g/n/jido_integration --mode lease`
  to keep lease records tenant-bound.

## Missing Proof Backlog

- `refactoring_deletion_backlog`: connect each 200-series deletion campaign to
  a StackLab scenario or explicit no-op proof.
- `agent_turn_runtime_patterns`: promote session-lineage drills into a named
  assembled-offline proof.
- `governed_connector_export_fixture`: prove redacted compliance export and
  credential export handling without raw secrets or provider payloads.
- `compliance_export_fixture`: prove redacted export bundle without raw
  prompts, provider payloads, secrets, or workflow histories.
