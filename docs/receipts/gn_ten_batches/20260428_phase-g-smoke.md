# gn-ten Batch Receipt: phase-g-smoke

Date: 2026-04-28
Batch ID: 20260428-phase-g-smoke
Branch policy: main_only
Run status: ok
Primary owner repo: stack_lab
Contract producer repo: 
Consumer repos: 

## Scope

- Goal: run repo-local gn-ten CI commands in fixed dependency order
- Non-goals: branch management, pushing, source mutation, live-provider proof
- Phase/checklist: Phase G CI And Batch Automation

## Commands

| Repo | Command | Status | Exit | Duration ms |
| --- | --- | --- | --- | --- |
| ground_plane | `mix ci` | ok | 0 | 25038 |
| execution_plane | `mix ci` | ok | 0 | 19146 |
| citadel | `mix ci` | ok | 0 | 100681 |
| jido_integration | `mix ci` | ok | 0 | 129947 |
| mezzanine | `mix ci` | ok | 0 | 223633 |
| outer_brain | `mix ci` | ok | 0 | 57196 |
| app_kit | `mix ci` | ok | 0 | 145032 |
| extravaganza | `mix ci` | ok | 0 | 53121 |
| AITrace | `mix deps.get && mix format --check-formatted && mix compile --warnings-as-errors && mix test && mix credo --strict && mix dialyzer --format short && mix docs` | ok | 0 | 6280 |
| stack_lab | `mix ci` | ok | 0 | 380878 |

## Proof

- Scenario: gn-ten repo-local CI batch
- Trace evidence: tmp/gn_ten_traces/phase-g-smoke.json
- Does not prove: production_deployment, live_provider_behavior, authoritative_audit_truth

## Git Closeout

| Repo | Branch | Commit SHA | Pushed | Clean |
| --- | --- | --- | --- | --- |
| ground_plane | main | fb2ee30d5b1c15ad8a6a165eeb54c31823ecc3ce | yes | yes |
| execution_plane | main | a2bd3c09b655f2ca82afc9ac1daa0eb326c079db | yes | yes |
| jido_integration | main | daed2a11a1eff02f022920e7984eb826b1a39c66 | yes | yes |
| citadel | main | 4051912adb0103bc9b2d768d85846de6272d946e | yes | yes |
| outer_brain | main | f438c5f14ca2efdc295ca477833a7c2500cbe565 | yes | yes |
| mezzanine | main | ad8fcf763837da1c09e21d17284d1ab2cf992a9f | yes | yes |
| app_kit | main | 03deb310faa614122b7df225b7e52f4f3734dfa8 | yes | yes |
| extravaganza | main | 1c6d9d31004c8c5dd3ce0ef89b6a494a1675ea30 | yes | yes |
| AITrace | main | cf64c782b8446b672e999317e2969ec94c0e11da | yes | yes |
| stack_lab | main | 871b5c6e91bac77dfcc09d2d63bd1b8e2cb46921 | yes | yes |

## Resume

_No resume point._

## Notes

- Public receipt fields intentionally omit raw command stdout and stderr.
