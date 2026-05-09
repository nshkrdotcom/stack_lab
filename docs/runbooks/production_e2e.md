# Extravaganza Production E2E

This runbook verifies the local single-node Extravaganza product path from
outside the product repo. StackLab is the acceptance harness; it is not product
runtime infrastructure.

Provider smoke remains separate. `mix stack_lab.provider_smoke_check` proves
provider reachability only and must not be used as the production E2E result.

## Local Substrate

Start the Mezzanine development substrate first:

```bash
cd /home/home/p/g/n/mezzanine
just dev-up
just dev-status
```

Start the StackLab single-node lab services when the scenario needs the lab
Postgres, Toxiproxy, or OpenTelemetry collector:

```bash
cd /home/home/p/g/n/stack_lab
just up-single
```

The acceptance command only checks Temporal through `just dev-status`; it must
not start or reset Temporal.

## Product Path

Run the product-local headless smoke from Extravaganza:

```bash
cd /home/home/p/g/n/extravaganza
mix extravaganza.headless.smoke --backend appkit
```

Run the StackLab acceptance check from the workspace root:

```bash
cd /home/home/p/g/n/stack_lab
mix stack_lab.production_e2e_check \
  --receipt-file /tmp/extravaganza-production-e2e.json
```

The receipt must include repo SHAs, runtime profile, scenario id, governed
lower envelope refs, lower runtime kind, lower receipt ref, projection ref,
review decision ref, and source publication receipt ref.

## Acceptance Steps

1. Start Mezzanine Temporal/Postgres substrate.
2. Bootstrap Extravaganza through the product installation path.
3. Admit one Linear-shaped subject through AppKit.
4. Start the run through `Extravaganza.ProductHost.start_run/2`.
5. Observe the Mezzanine workflow/outbox handoff.
6. Verify Citadel/Jido lower dispatch refs and lower runtime kind.
7. Deliver or observe a deterministic terminal lower receipt.
8. Read projection through AppKit.
9. Submit the operator review decision.
10. Confirm source publication receipt evidence.

## Required Claim Rows

The receipt must carry acceptance rows for:

- local single-node run
- no-bypass
- authority exact match
- active manifest required for writes
- deterministic lower receipt
- projection evidence chain
- review decision
- source publication receipt
- Symphony parity: source eligibility, continuation retry, abnormal retry,
  stale retry protection, workspace policy, dynamic tool denial, and
  observability state/detail/refresh
