# Up Single

Bring up the single-node harness:

```bash
just up-single
```

This command uses `tools/compose/single-node.yml`.

To validate Extravaganza from the assembled single-node workspace without
moving product ownership into StackLab, run the external acceptance task:

```bash
mix stack_lab.extravaganza.external_acceptance
```

The task shells out to `mix extravaganza.headless.smoke --deterministic
--same-run --json` in the Extravaganza repo, validates the returned public
receipt refs, and writes a StackLab receipt under `tmp/`. Provider smoke remains
separate and provider-only.
