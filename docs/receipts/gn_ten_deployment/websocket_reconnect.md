# gn-ten Deployment Rehearsal: Websocket reconnect

Drill: websocket_reconnect
Date: 2026-04-28
Profile: deployment_single_node
Branch policy: main_only
Owner repo: stack_lab
Command: `mix gn_ten.deploy.rehearse --drill websocket_reconnect`

## Proof Posture

- authoritative_audit?: false
- production_deployment_proven?: false
- safe_action: use_as_local_single_node_deployment_rehearsal

## Required Spans

- [x] sample_client_connected: pass
- [x] server_bounce_rehearsed: pass
- [x] client_reconnect_checked: pass
- [x] missed_event_readback_checked: pass

## Does Not Prove

- production edge failover
- browser compatibility
- large-fanout websocket load

## Notes

- This is a deterministic local rehearsal receipt.
- It is not a production deployment proof.
