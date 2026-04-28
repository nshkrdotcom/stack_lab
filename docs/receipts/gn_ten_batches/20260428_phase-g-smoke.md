# gn-ten Batch Receipt: phase-g-smoke

Date: 2026-04-28
Batch ID: 20260428-phase-g-smoke
Branch policy: main_only
Run status: dry_run
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
| ground_plane | `mix ci` | dry_run | 0 | 0 |
| execution_plane | `mix ci` | dry_run | 0 | 0 |
| citadel | `mix ci` | dry_run | 0 | 0 |
| jido_integration | `mix ci` | dry_run | 0 | 0 |
| mezzanine | `mix ci` | dry_run | 0 | 0 |
| outer_brain | `mix ci` | dry_run | 0 | 0 |
| app_kit | `mix ci` | dry_run | 0 | 0 |
| extravaganza | `mix ci` | dry_run | 0 | 0 |
| AITrace | `mix deps.get && mix format --check-formatted && mix compile --warnings-as-errors && mix test && mix credo --strict && mix dialyzer --format short && mix docs` | dry_run | 0 | 0 |
| stack_lab | `mix ci` | dry_run | 0 | 0 |

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
