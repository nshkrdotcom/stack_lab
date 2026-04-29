# gn-ten Deployment Rehearsal: Backup and restore

Drill: backup_restore
Date: 2026-04-28
Profile: deployment_single_node
Branch policy: main_only
Owner repo: stack_lab
Command: `mix gn_ten.deploy.rehearse --drill backup_restore`

## Proof Posture

- authoritative_audit?: false
- production_deployment_proven?: false
- safe_action: use_as_local_single_node_deployment_rehearsal

## Required Spans

- [x] postgres_backup_rehearsed: pass
- [x] database_drop_rehearsed: pass
- [x] restore_rehearsed: pass
- [x] projection_bootstrap_checked: pass
- [x] restore_trace_posture_checked: pass

## Does Not Prove

- live database destructive restore
- point-in-time recovery under production load
- disaster recovery RTO or RPO

## Notes

- This is a deterministic local rehearsal receipt.
- It is not a production deployment proof.
