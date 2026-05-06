# StackLab SpecCell

`StackLab.SpecCell` is the executable requirement cell package for release
tracks. It records the owner repo, source docs, target code paths, proof
command, acceptance fixture, scanner refs, closeout state, and release claim
for each fixture or phase row.

## Phase

Owner phase: `ADDL-PHASE-01`, Phase 0, Phase 1, and adaptive Phase 16.

## Contract

SpecCells are release-gate records. A cell is complete only when code evidence,
fixture evidence, scanner evidence, docs, receipts, and closeout state agree.
Adaptive release fixtures use the same cell contract for `AOC-*` and
`PERSIST-AOC-*` ids; an open defect cell can be mapped but is not complete.

## QC

```bash
mix test
mix format --check-formatted
```
