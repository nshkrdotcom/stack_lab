# gn-ten Proof Matrix

Date: 2026-04-28

This matrix maps the `gn-ten` contract docset to executable StackLab proof
ownership. The current ledger has no partial rows.

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
| `app_kit` | `repo://nshkrdotcom/app_kit` | product no-bypass and DTO conformance proofs, including Phase 15 adaptive-control operator sections | `mix ci` in `app_kit`; `mix test` in `stack_lab/support/no_bypass_scanner` | `AOC-044` no-bypass scan receipts and AppKit adaptive-control facade proof |
| `extravaganza` | `repo://nshkrdotcom/extravaganza` | product-owned headless and UI proofs plus StackLab external command validation | `mix ci` in `extravaganza`; `mix stack_lab.extravaganza.external_acceptance` in `stack_lab` | AppKit DTO, no-bypass, and external headless receipt refs |
| `stack_lab` | `repo://nshkrdotcom/stack_lab` | assembled proof owner, including Phase 16 release claim mapping | `mix ci`; `mix gn_ten.validate`; `mix test` in `support/gn_ten_control_plane` | proof matrix, scenario receipts, and `AOC-048` release proof |
| `AITrace` | `repo://nshkrdotcom/AITrace` | trace export and single-node proof-trace fixture | AITrace equivalent CI gate | `aitrace.single_node_proof_trace.v1` |

## Contract Family Coverage

| Contract Family | Owner | Proof Status | Next Action |
| --- | --- | --- | --- |
| 000 repo contracts | docs + repo owners | documentation complete | copy reviewed repo-agent instructions into repo roots |
| 100 development process | `stack_lab`, `AITrace` | StackLab development loop and local trace fixtures implemented | keep trace fixtures current with proof loop changes |
| 200 refactoring | repo owners | refactoring deletion backlog proof implemented with inventory, deletion campaign links, and retention/no-op receipts | keep inventory current and open concrete deletion campaigns when active candidates appear |
| 300 architecture | docs + `stack_lab` | manifest, artifact ledger, product no-bypass, and Context ABI roundtrip fixtures implemented | keep product and Context ABI fixture proofs wired into CI and expand fixtures as product shapes change |
| 400 agent patterns | `outer_brain`, `citadel`, `jido_integration`, `execution_plane` | connector provider-free, budget, and agent-turn runtime pattern proofs implemented | add live runtime drills only when release claims require them |
| 500 governance | `citadel`, `mezzanine`, `jido_integration` | tenant isolation, connector secret lease, prompt-injection fixtures, and governed connector compliance export fixture implemented | add incident export and production compliance-retention fixtures only when release claims require them |
| 600 deployment | `stack_lab`, `mezzanine`, `AITrace` | local single-node deployment rehearsal implemented | convert local rehearsals into clean-host operator drills once deploy scripts are repo-owned |

## Release Readiness Proof Profiles

| Profile | Scope | Required Evidence |
| --- | --- | --- |
| `local_quick` | manifest, repo refs, proof matrix, no-bypass scans | `mix gn_ten.validate`, focused repo tests |
| `local_full` | all repo-local CI gates in manifest order | command receipts and clean worktrees |
| `assembled_offline` | StackLab fixture-backed full graph | StackLab scenario receipts and AITrace fixture |
| `deployment_single_node` | single-node production rehearsal | deployment receipt, backup/restore receipt, trace export |

## Live Provider Claim Boundary

Phase 13 does not add a multi-product live-provider claim. Current live-provider
proof remains Extravaganza-scoped. Neutral product genericity remains
deterministic and provider-free through `examples/toy_document_review`.

The release boundary receipt is
`docs/receipts/gn_ten_phase13/live_neutral_claim_boundary.json`.

Any later neutral product live-provider claim must add a StackLab proof app under
`examples/<name>/mix.exs`, keep deterministic fake-provider acceptance, route
through the generic AppKit -> Mezzanine -> Citadel -> Jido -> Execution Plane
path, and run GitHub or Linear live commands by prefixing them with
`~/scripts/with_bash_secrets`.

## Implemented Fixture Proofs

- `refactoring_deletion_backlog`: runs the deterministic refactoring deletion
  backlog proof covering all ten target repos, named deletion campaigns,
  StackLab batch receipt links, and retention/no-op receipts with owner,
  reason, review date, and scanner posture.
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
- `restart_fencing_provider_free`: runs the provider-free StackLab restart and
  fencing scenario that denies duplicate dispatch during active delayed retry,
  stale installation revision dispatch, and revoked GroundPlane lease reuse
  after restart.
- `connector_provider_free`: runs the provider-free connector hardening
  scenario that normalizes fixture provider responses without live-provider
  calls or provider payload receipts.
- `connector_secret_lease`: runs the connector hardening scenario that exposes
  only an opaque lease handle and denies public secret-shaped keys.
- `connector_token_budget`: runs the connector hardening scenario that forces a
  budget exhaustion fallback before uncontrolled model/provider spend.
- `prompt_injection_defense`: runs the connector hardening scenario that rejects
  untrusted content attempting to expand tool permissions or alter policy.
- `agent_turn_runtime_patterns`: runs the session-lineage assembled proof with
  multi-turn recovery, dynamic tool manifest recovery, unauthorized tool
  fail-closed behavior, fault-injected fallback lane selection, repo evidence
  for OuterBrain, Citadel, Jido Integration, Execution Plane, Mezzanine, and
  AITrace, and AITrace lineage/replay event refs.
- `governed_connector_export_fixture`: runs the deterministic governed
  connector compliance export fixture with explicit AITrace export context,
  tenant-bound source/replay refs, connector binding refs, credential lease
  refs, lower receipt refs, redaction refs, shared GroundPlane boundary-codec
  hashes, and nested leak-negative checks for raw secrets, native auth material,
  prompt bodies, provider payloads, and untrusted content bodies.
- `gepa_platform_roundtrip`: runs the deterministic governed GEPA proof with
  mock model profiles, model inference scanner receipts, optimization fabric
  scanner receipts, AI run lineage receipts, promotion refs, rollback refs, and
  trace refs.
- `trinity_platform_roundtrip`: runs the deterministic governed TRINITY proof
  with mock route selection, role injection, provider pool readiness, verifier
  refs, handoff scope refs, AppKit coordination projections, coordination
  fabric scanner receipts, trace refs, and replay refs.
- `context_abi_roundtrip`: runs the deterministic fugu Context ABI proof from
  AppKit context-surface input through OuterBrain packet compile and render
  refs, Citadel authority, Mezzanine admission/routing/render handoff, Jido
  fake model invocation, AITrace bounded evidence, AppKit projections, and
  StackLab context/model/cost/lineage/tenant/memory scanner receipts.
- `nshkr_router_fabric_roundtrip`: runs the deterministic fugu router fabric
  proof from admitted Context ABI packet through
  `Trinity.MezzanineRouterAdapter`, Mezzanine render handoff, Jido fake model
  invocation, AITrace bounded route/model/eval facts, AppKit projections, and
  StackLab context/router/coordination/model scanner receipts.
- `fugu_single_node_readiness_handoff`: records the Phase 16 single-node
  provider-free handoff receipt that unblocks the `../nshkr_v2` distributed
  StackLab checklist. It names Context ABI, router fabric, and Extravaganza
  external acceptance as required upstream proofs, records that live provider
  checks are opt-in through explicit flags plus `~/scripts/with_bash_secrets`,
  and leaves distributed BEAM placement to v2.
- `fugu_release_claim_closeout`: records the Phase 17 fugu release claim
  closeout receipt. It maps each public fugu claim to source refs, tests, docs,
  scanners, QC commands, and receipts, while keeping live provider behavior,
  distributed BEAM placement, production persistence, credential rotation,
  provider billing, 49-node scale, and artifact freshness warnings outside the
  release claim until separately proven.
- `fugu_post_cutover_hardening`: records the Phase 18 hardening receipt. It
  captures a local resource snapshot, provider-free cost posture, covered
  failure fixture families, Context ABI extraction deferral, router/GEPA
  next-work decisions, and the `../nshkr_v2` handoff boundary.
- `gn_ten_distributed_topology_freeze`: records the v2 Phase 1 topology
  freeze. It validates canonical topology refs, owner repos, owner-defined
  discovery groups, required profiles, default and stress node caps, exact
  12/32/49 scale counts, and negative fixtures for unknown repos, duplicate
  node ids, missing required profiles, owner group mismatch, and node count
  over-cap. It does not prove EPMD startup, peer lifecycle, owner facade
  availability, distributed business semantics, monolith/distributed parity,
  or 49-node scale feasibility.
- `gn_ten_distributed_preflight`: records the v2 Phase 3 node-lab package
  preflight. It proves `support/gn_ten_node_lab` owns reusable preflight and
  peer lifecycle checks; EPMD can start; a shortname StackLab controller node
  can come up; a redacted per-run cookie can be generated; the planned
  distribution port range validates; frozen topology specs can be parsed with
  node-cap enforcement; a temporary peer can start, sync code paths, answer
  bounded `:erpc`, stop, and become unreachable after cleanup; listen-socket
  exposure is recorded; and existing multi-node proofs remain parallel in root
  CI until node-lab migration. It does not prove owner facades, domain
  semantics, parity, production security, per-run cookie application to peers,
  or release boot.
- `gn_ten_distributed_context_roundtrip`: records the v2 Phase 8 context
  distributed proof. It runs the fugu Context ABI baseline and distributed
  context scenario from `examples/gn_ten_distributed_stack`, represents
  AppKit, Mezzanine, Citadel, OuterBrain, and AITrace as distinct peer-node
  owner profiles, and records context packet hash, authority refs, render
  handoff refs, trace refs, evidence posture, owner `:pg` groups, and
  envelope scanner facts. It does not prove router/model invocation,
  Execution Plane lower lanes, production security, release boot, live
  provider behavior, or fault recovery.
- `gn_ten_distributed_router_model_roundtrip`: records the v2 Phase 9
  router/model distributed proof. It extends the context proof through the
  deterministic TRINITY router adapter, Mezzanine render handoff, Jido
  Integration fake/local model invocation, token/cost facts, stream fragment
  posture, and terminal AppKit projection. It does not prove the unbuilt
  `full_9_node` lower-lane proof, live provider behavior, production
  security, release boot, GEPA candidate generation, or TRINITY long-loop
  feedback behavior beyond the deterministic route fixture.
- `gn_ten_distributed_partition_recovery`: records the v2 Phase 11 fault and
  recovery proof. It starts from the implemented `router_model_6_node` proof
  and records bounded receipts for peer crash, node disconnect/heal, facade
  timeout, stale DTO, duplicate delivery, and AITrace exporter failure. It
  does not prove WAN partition behavior, Kubernetes/container discovery,
  production Erlang distribution security, live provider retry/billing,
  Execution Plane lower-lane partition behavior, or release boot.
- `gn_ten_distributed_parity`: records the v2 Phase 13 semantic parity proof.
  It runs the fugu router/model monolith baseline and distributed router/model
  proof from one command, hashes deterministic semantic fields with
  `GroundPlane.Boundary.Codec`, excludes placement/timing/transport evidence,
  and records open-defect findings for raw payload fields, unexpected semantic
  fields, missing fields, and terminal status mismatches. It does not prove
  production distribution security, release artifact boot, live provider
  behavior, 49-node scale behavior, or semantic equivalence outside the named
  parity field list.
- `gn_ten_distributed_scale_12`: records the v2 Phase 14 default scale proof.
  It boots and cleans up a 12-node local peer-mode topology, records node cap,
  node count, startup duration, scheduler flags, peer failure count, host
  resource summary, and cleanup status, enforces requested max-node caps before
  startup, and keeps 49-node stress execution blocked until explicit host
  feasibility fields are supplied. It does not prove 32/49-node local stress,
  sustained SLOs, production distribution security, release boot, or live
  provider behavior.
- `gn_ten_distributed_release_peer`: records the v2 Phase 16 release-path
  parity prototype. It verifies a test-only release-wrapper manifest for the
  `execution_plane_node` profile, records owner app start, expected app
  version, facade ping, code-path mode, and receipt-shape parity with peer
  mode, and emits bounded open-defect receipts for missing manifest, version
  mismatch, unavailable facade, and receipt-shape mismatch. It does not prove
  production release packaging, release artifact minimality, an all-domain
  production release, production distribution security, container/VM
  networking, or live provider behavior.
- `cost_budget_scanner`: verifies adaptive token, provider request,
  self-hosted GPU minute, endpoint startup, eval batch, replay, optimization
  search, provider pool turn, role budget, promotion, failed retry, budget
  exhaustion, AppKit projection, AITrace span, and redacted StackLab receipt
  refs.
- `adaptive_control_roundtrip`: runs the deterministic closed-loop proof with
  TRINITY trace refs, eval and replay dataset refs, GEPA target refs, candidate
  refs, shadow/canary/approval gates, promotion refs, rollback refs, stale
  artifact rejection refs, AppKit adaptive-control projections, scanner
  receipts, Phase 14 live-provider gate refs, Pristine OpenAPI admission refs,
  Prismatic GraphQL operation binding refs, durable persistence preflight refs,
  redacted debug sidecar refs, and no live provider dependency.
- `persistence_mode_roundtrip`: runs the deterministic persistence profile
  matrix for `:mickey_mouse`, `:memory_debug`, `:integration_postgres`, and
  `:full_debug_tracked`. The proof records storage behavior, stable authority
  semantics, restart-claim classification, redacted debug evidence, gn-ten
  profile/tier/store/capture/proof fields, and source/test/scanner/docs/receipt
  mappings for `PERSIST-001` through `PERSIST-020` without regex parsing,
  environment reads, live providers, Postgres, Temporal, object stores,
  network, optional external substrates, or raw debug payloads.

## Partial Proof Backlog

No proof matrix rows are currently partial.
