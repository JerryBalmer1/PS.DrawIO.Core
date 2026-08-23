# PS.DrawIO.Core
Serialization, layout, and XML emission for the PS.DrawIO ecosystem. Consumes provider declarations from PS.DrawIO.Registry.

## Schema validation

Every emission is validated in-process against a vendored copy of
[`mxfile.xsd`](src/Schema/mxfile.xsd) (from
[jgraph/drawio-mcp](https://github.com/jgraph/drawio-mcp), Apache-2.0).
See [ADR 0005](docs/DECISIONS/0005-vendoring-the-mxfile-schema.md). Use
`Test-PSDrawIODiagramSchema` directly, or rely on `Export-PSDrawIODiagram`
which validates before write.

## Agent execution protocol

Agent work follows [`.agent/TRAPS.md`](.agent/TRAPS.md): accumulated failure knowledge read once before any task. Per-run plans and attempt logs go in `.agent/EXECUTION.md` (gitignored). See [`.agent/README.md`](.agent/README.md).
