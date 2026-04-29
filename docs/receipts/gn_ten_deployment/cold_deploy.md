# gn-ten Deployment Rehearsal: Cold deploy

Drill: cold_deploy
Date: 2026-04-28
Profile: deployment_single_node
Branch policy: main_only
Owner repo: stack_lab
Command: `mix gn_ten.deploy.rehearse --drill cold_deploy`

## Proof Posture

- authoritative_audit?: false
- production_deployment_proven?: false
- safe_action: use_as_local_single_node_deployment_rehearsal

## Required Spans

- [x] local_container_teardown_rehearsed: pass
- [x] deploy_script_invoked_rehearsal: pass
- [x] health_endpoints_checked: pass
- [x] deployment_trace_exported: pass

## Does Not Prove

- clean-host production deployment
- Coolify server behavior
- container image provenance

## Notes

- This is a deterministic local rehearsal receipt.
- It is not a production deployment proof.
