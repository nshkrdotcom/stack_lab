# StackLab Generalized Stack Boundary

## Responsibility

StackLab owns proof composition: deterministic examples, scanner packages,
release receipts, proof matrix validation, batch receipts, AITrace fixture
exports, and external acceptance commands.

It does not own the product feature, governance decision, connector adapter,
runtime lane, semantic engine, or primitive contract under test.

## Public Interfaces

Primary public surfaces:

- root Mix tasks such as `mix ci`, `mix gn_ten.proofs.validate`,
  `mix gn_ten.connector.scan`, and `mix gn_ten.tenant.scan`;
- `proof_matrix.yml` and `docs/gn_ten_proof_matrix.md`;
- `docs/receipts/**`;
- `support/*` scanner and harness packages;
- `examples/*` proof apps;
- `fixtures/**` and `repo_agent_instructions/**`.

## Dependency Rules

Allowed dependencies:

- sibling repo packages only as needed for assembled proof apps;
- scanner packages that read source as data;
- AITrace/export contracts for trace evidence;
- GroundPlane primitives when proof receipts need shared hashes or refs.

Forbidden dependencies:

- proof apps that reimplement product logic instead of invoking product-owned
  commands for product claims;
- live-provider claims without deterministic provider-free baselines;
- raw secrets, raw provider payloads, or private prompts in public receipts;
- unsupervised proof workers.

## Provider Vocabulary Zoning

Provider terms may appear in fixtures, receipts, traces, live claim boundaries,
and connector proof rows. Every proof that mentions provider behavior must
state whether it is deterministic provider-free, live-provider proven, or
explicitly outside the current claim.

## Migration And Cleanup Ownership

StackLab cleanup work removes stale receipts, duplicated proof helpers,
obsolete scanner fixtures, and partial proof rows when implementation evidence
supersedes them. Retained historical receipts must say what they do and do not
prove.
