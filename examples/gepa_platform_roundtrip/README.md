# StackLab GEPA Platform Roundtrip

Deterministic governed GEPA roundtrip proof with mock model profiles, candidate
evaluation, comparison, promotion gates, rollback refs, and trace refs.

The proof path uses `GEPAFramework` plus `GEPA.MezzanineOptimizerAdapter`
through `Mezzanine.OptimizationEngine.propose_candidates/3`, then projects the
candidate through `AppKit.OptimizationSurface`. `gepa_buildout` is not required
for this canary.
