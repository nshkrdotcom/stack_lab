# Faults

Inject a named fault through the harness:

```bash
just fault net-cut
just fault high-latency
```

The current fault helpers target the local Toxiproxy endpoint.
