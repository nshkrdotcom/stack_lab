# StackLab Agent Foundation Roundtrip

Deterministic offline release proof for the native agent foundation. The proof
uses the actual AppKit, Mezzanine, Citadel, Jido Integration, Execution Plane,
AITrace, and StackLab scanner contracts while keeping live providers out of the
loop.

Run the proof as JSON:

```bash
mix stack_lab.agent_foundation.roundtrip --deterministic --json
```

The receipt covers the AF-001 through AF-019 acceptance matrix items. AF-020 is
reserved for the Extravaganza product smoke phase because that phase owns the
product live/provider exercise.
