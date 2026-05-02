# Atom Cleanup Harness

`StackLab.Examples.AtomCleanupHarness` records bounded dynamic-atom cleanup
evidence for the ATOM phase sequence.

## Phase

Owner phase: ATOM-01 through ATOM-35.

## Contract

The harness scans source text for known atom-conversion forms, records findings
with bounded classifications, blocks unresolved runtime external-input
findings, and emits SpecCell plus gn-ten receipt records for the target repo.

## QC

```bash
mix test
mix format --check-formatted
```
