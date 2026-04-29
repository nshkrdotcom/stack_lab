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

- Repo: stack_lab
- Branch: main
- Commit SHA:
- Pushed:
- Worktree clean:

## Resume

_No resume point._

## Notes

- Public receipt fields intentionally omit raw command stdout and stderr.
