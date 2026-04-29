# stack_lab Onboarding

Read `AGENTS.md` first; this repo is the practical command surface for gn-ten.
`CLAUDE.md` must stay a one-line compatibility shim containing `@AGENTS.md`.

## Owns

Full-graph assembled proofs, fault injection, restart drills, batch receipts,
the gn-ten manifest, proof matrix, validators, scanners, and local harnesses.

## Does Not Own

Production business logic, runtime service ownership, product UX, lower
execution implementation, or source-of-truth app code for other repos.

## First Task

```bash
cd /home/home/p/g/n/stack_lab
mix ci
mix gn_ten.plan --repo stack_lab
```

## Proofs

This repo owns `/home/home/p/g/n/stack_lab/proof_matrix.yml` and
`/home/home/p/g/n/stack_lab/docs/gn_ten_proof_matrix.md`.

## Common Changes

Keep validators descriptive and read-only unless a phase explicitly introduces
mutation. Receipts must avoid secrets, raw prompts, provider payloads, and
absolute workspace paths in public DTOs.
