# ADR 0005: Vendoring the mxfile schema

## Status
Accepted

## Context
CORE.md §7 and §8 require every XML document Core emits to be validated against
`mxfile.xsd` in-process via `System.Xml.Schema.XmlSchemaSet` before it is
considered successful output. Failure is a terminating error naming the
violation. Validation is not optional and is not a `-Debug` flag.

The canonical schema lives upstream at
[jgraph/drawio-mcp `shared/mxfile.xsd`](https://github.com/jgraph/drawio-mcp/blob/main/shared/mxfile.xsd).
Fetching it at runtime or in CI would make emission depend on network
availability and on an unpinned moving target. Core must ship a pinned copy.

Upstream license (repository SPDX + LICENSE file): **Apache License 2.0**,
Copyright 2025 JGraph Ltd. Core is MIT. Apache-2.0 permits redistribution with
attribution; vendoring is compatible provided the third-party notice is retained.

## Decision
1. **Vendor** `mxfile.xsd` at `src/Schema/mxfile.xsd`. Package copies the whole
   `src/` tree, so the schema ships in `dist/PS.DrawIO.Core/Schema/mxfile.xsd`
   without a special-case build step.
2. **Pin** the file by content SHA-256 and by the upstream git commit that last
   touched `shared/mxfile.xsd`. A unit test asserts the on-disk SHA-256 matches
   the value recorded here. Drift fails the suite.
3. **Resolve** the schema path from the loaded module root
   (`Resolve-PSDrawIOSchemaPath`: one `Split-Path` from `Private/` → module
   root → `Schema/mxfile.xsd`). Works for both `src/` import and packaged
   `dist/` import. No network at runtime, build, or CI.
4. **Validate** every emission through public `Test-PSDrawIODiagramSchema`
   before `Export-PSDrawIODiagram` writes a file. The XSD is the primary gate;
   structural root cells `id="0"` and `id="1" parent="0"` are enforced in the
   same function because the upstream schema documents them but does not
   express them as identity constraints.
5. **Refresh policy:** when upstream changes the schema, a human (or agent
   with explicit task) re-downloads, updates the SHA-256 pin and this ADR's
   provenance table, and re-runs the suite. Silent auto-refresh is forbidden.
6. **License:** acknowledge Apache-2.0 for the vendored file in `LICENSE`
   (Third-party notices) and briefly in `README.md`. Do not re-license the
   schema as MIT.
7. **Inherit upstream defects:** if the vendored XSD is wrong or incomplete
   relative to real draw.io files, Core inherits that defect until a deliberate
   pin refresh. Do not invent a parallel schema or silently loosen validation.

### Provenance (pin)

| Field | Value |
| --- | --- |
| Source URL | `https://raw.githubusercontent.com/jgraph/drawio-mcp/main/shared/mxfile.xsd` |
| Upstream path commit | `079768d7a0c8309a2f3052990945bc91eddf72ef` |
| Retrieval date (UTC) | `2026-08-23` |
| File SHA-256 | `905db85d4e8ebec0e91518cdd62982e0afb3f09ebdcaf9e6b1952957a606639a` |
| Upstream license | Apache License 2.0 (Copyright 2025 JGraph Ltd) |
| Git blob SHA (informational) | `53277111bc48ad6cccd259ad95a244eb9701e261` |
| Byte length | `29499` |

## Consequences
- Emission that fails schema validation throws with a message containing
  `schema` and naming the offending element/attribute/rule; no `.drawio` file
  is written.
- Packaging must keep `Schema/mxfile.xsd` next to the module root; path
  resolution is a regression surface (covered by a packaged-module unit test).
- UserObject emission places required `id` on the wrapper. Nested `mxCell` `id`
  is optional in the XSD (not forbidden). Core uses dual-id (wrapper + nested)
  per ADR 0006 Option A; import normalizes either form. Do not treat dual-id as
  a schema violation.
- Schema updates are deliberate, tested pin bumps — not drive-by downloads.
