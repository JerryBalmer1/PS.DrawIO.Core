# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

- Vendored `src/Schema/mxfile.xsd` (jgraph/drawio-mcp, Apache-2.0) and added `Test-PSDrawIODiagramSchema` (XmlSchemaSet in-process). `Export-PSDrawIODiagram` validates before write; schema failure is terminating and leaves no file (ADR 0005).
- ADR 0006 Option A: emit `UserObject` (with required `id`, `label`/`link`, preserved attrs) only when a cell has a link or preserved unknown attributes; bare `mxCell` otherwise. Nested `mxCell` keeps its own `id`. Import normalizes bare-cell and UserObject customs into the same `Metadata.XmlAttributes` bag. Regenerated golden `hand-unknown-attrs.drawio`.
- Added optional `-Resolver` seam on `ConvertTo-PSDrawIOIR` (ADR 0004): injected scriptblock receives Provider+Type, applies returned Style/LinkTemplate, fails loudly on null/throw naming both; no Registry dependency and no invented style when omitted or when declaration lacks Style.
- Added `Export-PSDrawIODiagram` and private DOM-based XML emission (`ConvertTo-PSDrawIODiagramXml`) for uncompressed `.drawio` output.
- Added `Invoke-PSDrawIOLayout` with a swappable strategy seam and a deterministic built-in grid/stack placer (`docs/LIMITATIONS.md`).
- Scaffolded repository harness (build, CI, acceptance shell, agent boundaries). No module source yet.
