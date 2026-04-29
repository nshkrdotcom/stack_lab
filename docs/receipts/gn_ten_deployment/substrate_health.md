# gn-ten Deployment Rehearsal: Substrate health

Drill: substrate_health
Date: 2026-04-28
Profile: deployment_single_node
Branch policy: main_only
Owner repo: stack_lab
Command: `mix gn_ten.deploy.rehearse --drill substrate_health`

## Proof Posture

- authoritative_audit?: false
- production_deployment_proven?: false
- safe_action: use_as_local_single_node_deployment_rehearsal

## Required Spans

- [x] mezzanine_substrate_health_invoked: pass
- [x] temporal_guardrail_checked: pass
- [x] postgres_health_checked: pass
- [x] provider_free_boundary_checked: pass
- [x] websocket_edge_health_checked: pass

## Does Not Prove

- live monitoring alert delivery
- provider uptime
- production websocket edge saturation

## Notes

- This is a deterministic local rehearsal receipt.
- It is not a production deployment proof.
