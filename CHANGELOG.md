# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

- Added `Export-PSDrawIODiagram` and private DOM-based XML emission (`ConvertTo-PSDrawIODiagramXml`) for uncompressed `.drawio` output.
- Added `Invoke-PSDrawIOLayout` with a swappable strategy seam and a deterministic built-in grid/stack placer (`docs/LIMITATIONS.md`).
- Scaffolded repository harness (build, CI, acceptance shell, agent boundaries). No module source yet.
