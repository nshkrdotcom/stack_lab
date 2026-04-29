# gn-ten Batch Review Checklist

Use this checklist at every gn-ten batch closeout. The receipt is the unit
of review; raw logs and private command output are not.

For shared-library plus governed-adapter work, also use
[`shared_library_governed_adapter_review.md`](shared_library_governed_adapter_review.md).

## Batch Identity

- [ ] Batch receipt path is named.
- [ ] Batch ID is present and unique.
- [ ] Branch policy is `main_only`.
- [ ] Primary owner repo is named.
- [ ] Cross-repo role is one of: producer, consumer, proof owner, none.

## Scope

- [ ] Goal is concrete and bounded.
- [ ] Non-goals are explicit.
- [ ] Phase checklist is linked.
- [ ] Any upstream amendment points to the lower owner repo and pushed SHA.

## Commands

- [ ] Every command has repo, command, result, and evidence.
- [ ] Repo-local CI is green for each repo in play.
- [ ] StackLab proof commands are green where assembled proof is claimed.
- [ ] No command output with secrets, prompts, provider payloads, or workflow
  histories is copied into public artifacts.

## Proof

- [ ] Proof matrix id exists or `not-applicable` is justified.
- [ ] Proof scenario is named.
- [ ] `does_not_prove` is filled.
- [ ] Trace evidence is present.
- [ ] Trace posture has `authoritative_audit?: false`.
- [ ] Trace posture has `production_deployment_proven?: false`.

## Public Hygiene

- [ ] No raw prompts.
- [ ] No provider payloads.
- [ ] No secrets, API keys, or token-shaped fields.
- [ ] No workflow histories.
- [ ] No private memory or audit content.

## Git Closeout

- [ ] Every changed repo is on `main`.
- [ ] Every changed repo has a pushed SHA.
- [ ] Every changed repo has a clean worktree.
- [ ] Docs are committed last.

## Reviewer Summary

Run:

```bash
mix gn_ten.review.summary --batch <slug>
```

The command must pass before the batch is treated as closed.
