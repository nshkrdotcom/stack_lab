# gn-ten Proof Matrix

Date: 2026-04-28

This matrix maps the `gn-ten` contract docset to executable StackLab proof
ownership. Entries marked `missing-proof` are intentional backlog items, not
claims of completed behavior.

## Repository Coverage

| Repo | Repo Ref | Current Proof Posture | Command | Evidence |
| --- | --- | --- | --- | --- |
| `ground_plane` | `repo://nshkrdotcom/ground_plane` | contract package CI plus future artifact ledger proof | `mix ci` in `ground_plane` | projected `ground_plane_contracts` artifact |
| `execution_plane` | `repo://nshkrdotcom/execution_plane` | lower lane and node proofs through StackLab | `mix ci` in `execution_plane`; StackLab lower runtime scenarios | lower outcome refs |
| `jido_integration` | `repo://nshkrdotcom/jido_integration` | connector/lower gateway proofs through StackLab | `mix ci` in `jido_integration`; StackLab connector scenarios | review packet and lower receipt refs |
| `citadel` | `repo://nshkrdotcom/citadel` | policy packet and authority proofs through StackLab | `mix ci` in `citadel`; StackLab governance scenarios | authority refs |
| `outer_brain` | `repo://nshkrdotcom/outer_brain` | restart durability and semantic failure proofs | `mix ci` in `outer_brain`; StackLab restart scenarios | semantic failure and journal refs |
| `mezzanine` | `repo://nshkrdotcom/mezzanine` | lifecycle, projection, audit, Temporal/Postgres drift proofs | `mix ci` in `mezzanine`; StackLab projection drift scenarios | projection and incident refs |
| `app_kit` | `repo://nshkrdotcom/app_kit` | product no-bypass and DTO conformance proofs | `mix ci` in `app_kit`; StackLab product-boundary scenarios | no-bypass scan receipts |
| `extravaganza` | `repo://nshkrdotcom/extravaganza` | thin product and headless parity proofs | `mix ci` in `extravaganza`; StackLab product lane fixture | AppKit DTO receipt refs |
| `stack_lab` | `repo://nshkrdotcom/stack_lab` | assembled proof owner | `mix ci`; `mix gn_ten.validate` | proof matrix and scenario receipts |
| `AITrace` | `repo://nshkrdotcom/AITrace` | trace export and single-node proof-trace fixture | AITrace equivalent CI gate | `aitrace.single_node_proof_trace.v1` |

## Contract Family Coverage

| Contract Family | Owner | Proof Status | Next Action |
| --- | --- | --- | --- |
| 000 repo contracts | docs + repo owners | documentation complete | copy reviewed repo-agent instructions into repo roots |
| 100 development process | `stack_lab`, `AITrace` | partial source-backed proof | add trace fixtures for local proof loops |
| 200 refactoring | repo owners | missing-proof | link each deletion campaign to a StackLab scenario or no-op proof |
| 300 architecture | docs + `stack_lab` | manifest validator starts proof | add contract artifact ledger |
| 400 agent patterns | `outer_brain`, `citadel`, `jido_integration`, `execution_plane` | partial source-backed proof | add dynamic tool manifest and session proof rows |
| 500 governance | `citadel`, `mezzanine`, `jido_integration` | partial source-backed proof | add incident/compliance export fixtures |
| 600 deployment | `stack_lab`, `mezzanine`, `AITrace` | missing-proof | add single-node deployment rehearsal receipt |

## Release Readiness Proof Profiles

| Profile | Scope | Required Evidence |
| --- | --- | --- |
| `local_quick` | manifest, repo refs, proof matrix, no-bypass scans | `mix gn_ten.validate`, focused repo tests |
| `local_full` | all repo-local CI gates in manifest order | command receipts and clean worktrees |
| `assembled_offline` | StackLab fixture-backed full graph | StackLab scenario receipts and AITrace fixture |
| `deployment_single_node` | single-node production rehearsal | deployment receipt, backup/restore receipt, trace export |

## Missing Proof Backlog

- `contract_artifact_ledger`: validate projected artifact SHAs against local
  producer repos.
- `repo_agent_instruction_drift`: verify repo-local `AGENTS.md` sections match
  reviewed cleanup drafts.
- `single_node_deployment_rehearsal`: prove Coolify-style release, migration,
  health check, trace export, and restore.
- `compliance_export_fixture`: prove redacted export bundle without raw
  prompts, provider payloads, secrets, or workflow histories.
