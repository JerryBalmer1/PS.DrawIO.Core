# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

- Added optional `-Resolver` seam on `ConvertTo-PSDrawIOIR` (ADR 0004): injected scriptblock receives Provider+Type, applies returned Style/LinkTemplate, fails loudly on null/throw naming both; no Registry dependency and no invented style when omitted or when declaration lacks Style.
- Added `Export-PSDrawIODiagram` and private DOM-based XML emission (`ConvertTo-PSDrawIODiagramXml`) for uncompressed `.drawio` output.
- Added `Invoke-PSDrawIOLayout` with a swappable strategy seam and a deterministic built-in grid/stack placer (`docs/LIMITATIONS.md`).
- Scaffolded repository harness (build, CI, acceptance shell, agent boundaries). No module source yet.
