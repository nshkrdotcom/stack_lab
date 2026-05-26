# StackLab Acceptance

StackLab acceptance is receipt-based. A proof is not closed by a passing smoke
command alone; it must have a proof-matrix row, scanner refs, docs refs, QC
refs, and generated artifacts under ignored or temp paths.

## Closeout Requirements

- checked-in proof fixture or SpecCell;
- deterministic command;
- bounded JSON receipt;
- scanner output for no-bypass, tenancy, payload, model, lineage, cost, and
  persistence where applicable;
- owner repo QC refs for every mutated repo;
- proof-matrix row with status and open defects;
- clean worktree after generated artifact cleanup.

## Local QC

```bash
mix gn_ten.proofs.validate --json
mix gn_ten.artifacts.validate --json
mix weld.verify
```

`mix gn_ten.artifacts.validate --json` must have zero failures before a release
claim closes. Bootstrap artifact rows may report stale-source warnings while
their owner packages are still pre-release; those warnings are evidence to
carry forward, not release blockers. Stable or deprecated artifacts must be
refreshed or demoted before closeout.
