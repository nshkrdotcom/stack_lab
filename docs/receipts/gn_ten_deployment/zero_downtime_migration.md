# gn-ten Deployment Rehearsal: Zero-downtime migration

Drill: zero_downtime_migration
Date: 2026-04-28
Profile: deployment_single_node
Branch policy: main_only
Owner repo: stack_lab
Command: `mix gn_ten.deploy.rehearse --drill zero_downtime_migration`

## Proof Posture

- authoritative_audit?: false
- production_deployment_proven?: false
- safe_action: use_as_local_single_node_deployment_rehearsal

## Required Spans

- [x] backward_compatible_migration_reviewed: pass
- [x] feature_flag_off_smoke: pass
- [x] read_write_during_migration_smoke: pass
- [x] feature_flag_toggle_smoke: pass
- [x] projection_rebuild_not_required: pass

## Does Not Prove

- production online DDL safety
- real concurrent write traffic
- database engine-specific lock behavior

## Notes

- This is a deterministic local rehearsal receipt.
- It is not a production deployment proof.
