# ADR 0006: Schema validation conflicts with attribute preservation

## Status
Accepted

## Context
CORE.md §8 states two Correctness gates that both apply to every emission:

> Every XML document Core emits is validated against `mxfile.xsd` (and the structural rules in §7) before it is considered successful output. Not optional. Not a `-Debug` flag. Failure is a terminating error naming the violation.

and, under the round-trip property test:

> Unknown attributes encountered on read are **preserved and re-emitted** unless explicitly overridden.

The vendored `src/Schema/mxfile.xsd` (present in the working tree from the killed XSD run; also in `stash@{0}`) encodes a shape that collides with how Core preserves attributes today:

- `UserObjectType` declares `id` with `use="required"` and ends with `xs:anyAttribute processContents="lax"` — custom metadata is legal on `UserObject` / `object`.
- `mxCellType` lists a closed set of attributes (`id`, `parent`, `value`, `style`, `vertex`, `edge`, `connectable`, `source`, `target`, `collapsed`, `visible`) and has **no** `xs:anyAttribute`. An undeclared attribute such as `customAttr` on a bare `mxCell` is schema-invalid.
- Schema documentation for nested cells says the wrapper carries the id; nested `mxCell` id is optional when inside `UserObject` / `object`.

Core emission on `main` today (`src/Private/ConvertTo-PSDrawIODiagramXml.ps1`, unstashed tree):

- Unknown attributes from `Metadata.XmlAttributes` are applied with `SetAttribute` onto the bare `mxCell`.
- A `UserObject` wrapper is created only when a link is present; the wrapper sets `label` and `link` but **does not** set `id` on the wrapper. The nested `mxCell` keeps `id`.
- Edges with `XmlAttributes` likewise stamp customs onto the bare edge `mxCell`.

The checked-in golden `tests/Fixtures/Golden/hand-unknown-attrs.drawio` is the bare-`mxCell` form (`customAttr="keep-me"` on `<mxCell id="u1" ...>`). The acceptance checkbox **Unknown attributes encountered on read are preserved and re-emitted** currently **passes** against that shape.

Therefore a diagram that preserves unknown attributes the way Core does today cannot pass `mxfile.xsd` validation. Turning on the §8 XSD gate without changing emission (or the gate, or CORE.md) would break the attribute-preservation acceptance path.

`git stash show -p stash@{0}` was readable. The killed run had already started reshaping emission toward UserObject wrapping (custom attrs and required `id` on the wrapper; golden rewritten to UserObject form; import promoting wrapper id). That stash is evidence of the collision and of one attempted resolution path. It was **not** applied; this ADR records the conflict only.

## Options
No recommendation. Each option's cost:

### A. Reshape emission to wrap attribute-carrying cells in `UserObject`
Put required `id` and custom attributes on the wrapper; keep visual flags on the nested `mxCell`.

**Cost:** Changes the emitted format for any cell that carries unknown attributes (and likely for linked cells). Invalidates the golden corpus (at least `hand-unknown-attrs.drawio`). Touches import (`ConvertFrom-PSDrawIODiagramXml`) so round-trip IR stays stable. Acceptance bodies that match bare-`mxCell` attribute placement may need review even if label text stays the same.

### B. Validate against a relaxed local schema rather than the vendored one
Allow `anyAttribute` on `mxCell`, or otherwise loosen the gate.

**Cost:** Weakens the gate CORE.md §8 calls non-negotiable ("validated against `mxfile.xsd`"). Diverges from the upstream schema pin (ADR 0005). A document that "passes" Core may still be invalid against the real draw.io schema.

### C. Exempt attribute-carrying diagrams from validation
Skip or soften schema validation when unknown attributes are present.

**Cost:** Creates a path where emission is unvalidated. Two diagrams that differ only by a preserved GUI attribute would take different correctness paths. Undermines "not optional / not a `-Debug` flag."

### D. Revisit whether both requirements can coexist, and change CORE.md
Drop, narrow, or rewrite one or both §8 gates and the matching §9 checkboxes.

**Cost:** Spec change. Touches CORE.md (out of band for implementation agents without explicit approval). May re-open acceptance labels and golden expectations. Does not by itself fix emission or validation code.

## Decision
**Option A** is accepted.

- A cell carrying preserved unknown attributes, **or** a link, is wrapped in
  `UserObject`. The `UserObject` carries `id` and the custom attributes (and
  `link` / `label` when present). The nested `mxCell` keeps its own `id` as
  well — the schema permits dual id, and several tests assert on `mxCell` ids.
- Cells with neither a link nor preserved attributes stay a bare `mxCell`.
  Do not wrap everything.
- **Option B rejected:** relaxing the schema weakens a gate CORE.md calls
  non-negotiable.
- **Option C rejected:** exempting diagrams from validation creates an
  unvalidated emission path — the same mechanism rejected in
  Provider.PowerShell ADR 0004.
- **Option D not needed.** CORE.md was right; the emitter was wrong.

## Consequences
- The emitted format changes for any cell with a link or preserved attributes,
  so the golden corpus must be regenerated for those fixtures.
- Import must read attributes from `UserObject` as well as from bare `mxCell`,
  and normalise both into the same IR shape (`Metadata.XmlAttributes`), or
  `parse → emit → parse` breaks.
- This reshape is a **prerequisite** for schema validation, which remains a
  separate slice (do not implement XSD validation in the reshape change).
- CORE.md §9 labels still in the blast radius once validation lands:

**Correctness gates**
- Every emission is validated against `mxfile.xsd` in-process via `XmlSchemaSet`
- Emission that fails schema validation throws, naming the violation
- `parse → emit → parse` is stable for a file Core wrote
- `parse → emit → parse` is stable for a hand-edited file Core did not write
- Unknown attributes encountered on read are preserved and re-emitted
- A golden-file corpus exists and a change to any golden file fails the suite

**Emission**
- `Export-PSDrawIODiagram` writes a `.drawio` file from an IR
- Cell ids are unique within a diagram
- Applies a declared `LinkTemplate` to the emitted `UserObject`

**Proof / Quality**
- Renders `PS.DrawIO.Provider.PowerShell`'s graph of itself, end to end, to a file that opens in draw.io
- Pester 5 green on Windows and Linux — PowerShell 7+