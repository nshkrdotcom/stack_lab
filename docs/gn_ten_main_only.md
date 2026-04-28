# gn-ten Main-Only Workspace

`gn-ten` is a sequential local workspace control plane. It is not a branching
workflow.

All ten repos stay on `main`. Coordination happens through:

- `gn-ten.yml`
- `mix gn_ten.validate`
- `mix gn_ten.status`
- proof-matrix entries
- docs/checklist updates
- pushed commit SHAs

## Invariant

Every manifest entry must declare:

```yaml
default_branch: main
```

The manifest itself must declare:

```yaml
branch_policy: main_only
```

The validator rejects any other branch policy or default branch. The status
command then checks the actual local checkout for every repo and reports:

- expected branch
- actual branch
- current SHA
- dirty worktree state
- ahead/behind counts when an upstream exists

## Non-Goals

`gn-ten` commands do not create, check out, reset, rebase, merge, or delete
branches. They are read-only coordination and verification tools until an
explicit future checklist says otherwise.

## Commands

```bash
mix gn_ten.validate
mix gn_ten.validate --json
mix gn_ten.status
mix gn_ten.status --json
```

Run `mix gn_ten.status` before starting a cross-repo batch and after pushing
the batch. A clean status means the local workspace is on `main`, all tracked
repos have a HEAD SHA, and no repo has uncommitted work.
