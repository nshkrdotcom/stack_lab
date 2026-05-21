# StackLab Replay Roundtrip

End-to-end replay proof showing replay side-effect suppression, divergence
projection, and bounded drift signals.

The proof also emits an AITrace agent evidence export through
`AITrace.Integrations.AgentTurn`. The export is ref-only: it carries ledger,
authority, runtime receipt, redaction manifest, and payload hash refs while
rejecting raw prompt/provider/event payloads and missing ledger sequence
coverage.
