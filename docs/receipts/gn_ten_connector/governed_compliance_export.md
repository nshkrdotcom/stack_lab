# gn-ten Governed Connector Compliance Export Receipt

Schema: `gn_ten_governed_connector_export_v1`

Profile: `assembled_offline`

Receipt: `receipt://stack_lab/governed_connector_export_fixture/latest`

Export ref: `export://stack-lab/governed-connector-export/github/v1`

Bundle hash: `sha256:619b44136054db484bb3f61a63c4dfd92f1ac6d6bdbaf5d565428e9dc8986cf7`

Spill hash: `sha256:8035ce7ffe5bb32aaa63f538dc56d82a6e50df703ec897b7a3b2ab0286e73eda`

Canonical boundary codec: `ground-plane.boundary.codec.v1`

## Proves

- The governed connector export fixture is deterministic and codec-backed.
- The fixture requires an explicit governed AITrace exporter and export context.
- Source traces and replay exports carry tenant refs and fail closed on missing or cross-tenant replay refs.
- Connector binding refs, credential lease refs, lower receipt refs, and redaction refs are enough for audit joins.
- Public export artifacts deny raw secrets, native auth material, prompt bodies, provider payloads, and untrusted content bodies.

## Does Not Prove

- live provider behavior
- production secret backend behavior
- production compliance export retention
- operator-facing compliance UI behavior
