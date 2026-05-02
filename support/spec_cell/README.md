# StackLab SpecCell

`StackLab.SpecCell` is the executable requirement cell package for the
universal auth authority release track. It records the owner repo, source docs,
target code paths, proof command, acceptance fixture, scanner refs, closeout
state, and release claim for each fixture or `ADDL-PHASE`.

## Phase

Owner phase: `ADDL-PHASE-01`, Phase 0, and Phase 1.

## Contract

SpecCells are release-gate records. A cell is complete only when code evidence,
fixture evidence, scanner evidence, docs, receipts, and closeout state agree.

## QC

```bash
mix test
mix format --check-formatted
```
