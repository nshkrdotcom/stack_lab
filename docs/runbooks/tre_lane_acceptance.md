# Neutral TRE Lane Acceptance

This runbook verifies the lower TRE lane from outside the owner repos. StackLab
is the acceptance harness only; production logic remains in Mezzanine, Jido
Integration, and ExecutionPlane.

## Default Fixture Runner

Run the deterministic subprocess-contract case:

```bash
cd /home/home/p/g/n/stack_lab
mix stack_lab.tre_lane_check \
  --receipt-file /tmp/stack-lab-tre-lane.json
```

This drives:

```text
StackLab
-> Mezzanine.IntegrationBridge.DirectRunDispatcher
-> Jido.Integration.V2.invoke
-> Jido.Integration.V2.RuntimeRouter.ExecutionPlaneTreAdapter
-> ExecutionPlane.Process.TreRhai
```

The fixture runner exists only to make the acceptance deterministic when
`rex-runner` is not installed. It still runs through the same ExecutionPlane
subprocess contract, cleared environment, materialized script/policy files, and
structured receipt path.

## Operator-Supplied Runner

When a real `rex-runner` binary is available, pass it explicitly:

```bash
cd /home/home/p/g/n/stack_lab
mix stack_lab.tre_lane_check \
  --runner-path /absolute/path/to/rex-runner \
  --receipt-file /tmp/stack-lab-tre-lane-real-runner.json
```

The receipt records:

- `scenario_id`
- repo SHAs
- runtime profile ref
- policy bundle hash
- Cedar schema hash
- script hash
- runner hash
- ExecutionPlane receipt ref
- Jido governed lower receipt ref
- Mezzanine governed lower receipt ref
- projection ref
- artifact refs and event refs

This check does not import or execute Extravaganza internals.
