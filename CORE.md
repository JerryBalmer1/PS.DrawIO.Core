# PS.DrawIO.Core

**Serialization, layout, and XML emission for the PS.DrawIO ecosystem.**

This repository ships exactly one module. It turns provider graphs — resolved through `PS.DrawIO.Registry` — into valid `.drawio` files. Domain knowledge does not live here. Contract brokering does not live here. Composition of multiple providers' graphs does not live here in v1.

Read `REGISTRY.md` in the registry repository first. Core is a consumer of that contract and of provider declarations; it does not redefine either.

---

## 1. What this is

`PS.DrawIO.Core` is the module that:

- Accepts a **provider graph** (or an equivalent front-end IR) and normalizes it into Core's intermediate representation
- **Resolves** semantic types through `PS.DrawIO.Registry` (`Resolve-PSDrawIOShape`) into styles, layout hints, and link templates
- Runs ordered **passes** over the IR (theme, measure, layout, route, emit)
- Owns **geometry** — every vertex and edge that lands on disk has coordinates Core chose
- Emits **uncompressed draw.io XML**, validates it, and writes `.drawio` files

Core applies declarations. It does not author them.

---

## 2. What this is not

Stated plainly, because scope creep here is the most likely way the ecosystem fails:

| Not this | Lives in |
|---|---|
| Provider contract definition, validation, registration | `PS.DrawIO.Registry` |
| Shape / theme / link / layout-hint *declarations* | `PS.DrawIO.Provider.*` via the registry |
| Domain extraction (AST, HCL, cloud APIs, …) | `PS.DrawIO.Provider.*` |
| Multi-provider graph composition (v1) | **Undecided** — see §3 |
| The `.drawio.ps1` DSL | `PS.DrawIO.Dsl` |
| Theme *contents* beyond applying declared defaults | Provider repositories |

Core stores no provider vocabulary of its own. If a semantic type is unknown, the registry throws; Core does not invent a style.

---

## 3. Composition is out of scope for v1

This is the most important boundary in this document.

Registry ADR 0003 Decision 5 left multi-provider composition ownership open:

> Nothing in any current specification describes a component that composes multiple providers' graphs. `REGISTRY.md` §4 assigns Core geometry and XML emission, which does not include composition. Therefore either Core's scope expands or a component is missing; that choice is not made here.

— `PS.DrawIO.Registry` `docs/DECISIONS/0003-cross-provider-references.md`

**Consequences for Core v1:**

- Core renders **one provider's graph at a time**
- Nothing in this module joins, merges, or overlays graphs from more than one registered provider
- Dual registration in the registry proves **coexistence**, not join — Core must not treat it as join
- Whether Core's scope later expands, or a separate composition component appears, is **undecided**
- An agent **must not** build multi-provider composition unasked. Record signals in `docs/COMPOSITION-SIGNALS.md`; do not decide ownership by implementing it

Core ADR 0001 qualifies node Ids (`Provider:Type:Name`) as a **cheap hedge** against a future join — not as proof that composition was decided, and not as license to build it.

---

## 4. The intermediate representation

Providers speak domain graphs (for example `PSModuleGraph`). Core speaks an IR that is already diagram-shaped: every node and edge carries what emission needs after registry resolution.

### Node Ids

Every IR node Id is **provider-qualified** per Core ADR 0001:

```
Provider:Type:Name
```

Example: `PowerShell:Function:Get-Thing` — not `Function:Get-Thing`.

- `Provider` — registered provider name (PascalCase, no dots)
- `Type` — semantic type key used with `Resolve-PSDrawIOShape -Type`
- `Name` — provider-local identity string

Providers may keep internal Ids; Core normalizes at the boundary it owns. Qualification costs nothing on the single-provider path and is nearly impossible to retrofit once golden files, links, and cell ids depend on bare Ids.

### What an IR node carries

Concrete fields the IR needs that a raw provider graph does not always have:

| Concern | Role |
|---|---|
| `Id` | Provider-qualified stable key |
| `Provider` / `Type` / `Name` | Split form of the Id for resolution and diagnostics |
| `Label` | Display text (becomes cell `value`, XML-escaped when HTML) |
| `ResolvedStyle` | Style string after registry resolve + theme |
| `Geometry` | `x`, `y`, `width`, `height` — owned by Core after layout |
| `ParentId` | Group / swimlane parent when nested; child coordinates are **relative to the parent**, not the canvas |
| `Link` | Optional URL or `vscode://` target injected via `UserObject` / `object` |
| `Metadata` | Opaque extras preserved for round-trip and custom properties |
| `Variant` | Optional declaration variant (for example Public / Private) when the provider uses variants |

### What an IR edge carries

| Concern | Role |
|---|---|
| `Id` | Stable edge identity within the diagram |
| `From` / `To` | Endpoint node Ids (qualified), never bare display names |
| `Type` | Semantic edge kind resolved through the registry when styled |
| `ResolvedStyle` | Edge stroke / arrow style after resolve + theme |
| `Waypoints` / routing data | Owned by Core after the route pass |
| `Aggregates` | Optional call-count or extent summary carried from the provider graph |

The IR is plain PowerShell data at module boundaries (`PSCustomObject` + `PSTypeName`). PS classes stay internal.

### Closed input, closed output

Provider graphs that feed Core are expected to be **closed**: every edge endpoint names a node Id present in that graph (placeholders for external / unresolved ends are the provider's job). Core does not silently drop edges with missing ends; it fails the contract at the boundary.

---

## 5. Layout is a swappable pass

### Verified layout finding

A `.drawio` file written to disk and opened renders at its **stored coordinates**.

- `childLayout=` runs only in response to **editor edits**
- `applyLayouts` exists only in the `#create` **URL hash**
- `--layout` is a **Desktop CLI** flag
- None of these is a file-level attribute that rearranges cells on open

**Consequence:** Core owns geometry. Emit `(0,0)` for everything and the user sees a pile on the origin.

### Three strategies, one interface

The architecture must let Core **swap** strategies rather than marry one:

| Strategy | Nature |
|---|---|
| 1. Compute coordinates in PowerShell | Full control, offline, most work |
| 2. Shell out to draw.io Desktop CLI `--layout` | Real engine, binary dependency |
| 3. Emit a `#create` URL with `applyLayouts` | No layout code in-process; output is a link |

These are three implementations of **one layout interface**. Providers declare **hints** ("these are siblings that should stack"). Core decides what a hint means in pixels — or which strategy runs. Providers never ship placement code into the shared pipeline.

If a provider ever needs custom placement, it registers a **named strategy** against that interface; Core invokes it. Arbitrary script injected into the layout pass is forbidden.

---

## 6. The pipeline

```
   Front-end / provider adapter
        │  domain graph → IR (Ids qualified, ends closed)
        ▼
   Resolve          registry: style, hints, link templates
        │
        ▼
   Theme            apply theme variables / defaults to styles and metrics
        │
        ▼
   Measure          text and padding → preferred width/height
        │
        ▼
   Layout           assign x/y (swappable strategy; see §5)
        │
        ▼
   Route            edge waypoints / orthogonal choices
        │
        ▼
   Emit             mxGraphModel (+ mxfile wrapper when required) → validate → write
```

### Why theme runs before layout

Themes change **font**, **padding**, and default style metrics. Those change measured **size**. Size changes **geometry**. Layout that runs before theme measures the wrong boxes and places them wrong. Theme is not cosmetic frosting after coordinates are fixed; it is an input to measure and layout.

### Front-ends and back-ends

- **Front-ends** produce IR (provider adapters, later the DSL, tests, fixtures)
- **Ordered passes** transform IR in place or as pure stages — order above is fixed for v1 reasoning even when a pass is a no-op
- **Back-ends** emit: primary back-end is uncompressed `.drawio` XML; a layout strategy may instead yield a `#create` URL when that strategy is selected

---

## 7. Hard format rules

Non-negotiable emission rules (verified; do not invent beyond these):

- Every diagram includes `<mxCell id="0"/>` and `<mxCell id="1" parent="0"/>`
- **Uncompressed XML only**
- **XML comments are strictly forbidden** — they cause parse errors
- Ids are unique within a diagram
- `vertex="1"` and `edge="1"` are mutually exclusive on a cell
- Non-rectangular shapes need a matching `perimeter=` value
- HTML in `value` must be XML-escaped
- Children of groups use coordinates **relative to the parent**, not the canvas

### Wrapper and metadata facts that shape the design

- A bare `<mxGraphModel>` is valid alone; the `<mxfile>` / `<diagram>` wrapper is required for multi-page documents
- File-level **vars** exist only on the full `<mxfile>` form — themes-via-variables force the wrapper
- `UserObject` / `object` carries custom metadata **and** the `link` attribute — semantic typing and clickable links are one mechanism

### Reference artifacts

Core's kernel is built against:

- [draw.io Style Reference](https://www.drawio.com/docs/reference/diagram-generation/style-reference/)
- [mxfile.xsd](https://github.com/jgraph/drawio-mcp/blob/main/shared/mxfile.xsd) — structural validation
- [shared/xml-reference.md](https://github.com/jgraph/drawio-mcp/blob/main/shared/xml-reference.md) — canonical generation rules
- JSON layout specification (draw.io layout docs used by the chosen strategy)

PowerShell 7 provides `System.Xml.Schema.XmlSchemaSet` natively. Core validates every emission **in-process** with no external schema tooling. That is a hard correctness gate, not a convention.

If a needed mxCell behavior is not listed here or in those references, **stop and say so** — do not guess.

---

## 8. Correctness gates

Three gates keep the kernel safe. They are requirements, not debug niceties.

### 1. XSD validation on every emission

Every XML document Core emits is validated against `mxfile.xsd` (and the structural rules in §7) before it is considered successful output. Not optional. Not a `-Debug` flag. Failure is a terminating error naming the violation.

### 2. Round-trip property test

```
parse → emit → parse
```

must be stable — including for files **Core never wrote**. Hand-edited GUI diagrams fed back in must survive. Unknown attributes encountered on read are **preserved and re-emitted** unless explicitly overridden. A GUI-edited diagram carries styles Core will never generate; dropping them destroys the user's work.

### 3. Golden-file corpus

A checked-in corpus of inputs and expected object trees (and/or canonical XML) pins kernel behavior. Any change that alters a golden file must be deliberate and reviewed — not an accidental drift from a "harmless" refactor.

---

## 9. Definition of Done — v1.0.0

> **This section drives the acceptance suite.** Every checkbox needs a matching
> `It` block in `tests/Acceptance/`, keyed by label text, and a meta-test
> enforces it. If an item is unchecked, v1 is not done. If it is not listed, it
> is not required for v1. Editing a checkbox edits the test suite.

### Contract consumption
- [ ] Resolves each semantic type through an injected resolver and applies whatever declaration is returned
- [ ] A resolver failure surfaces as a terminating error naming the type and the provider
- [ ] Applies a declared `LinkTemplate` to the emitted `UserObject`
- [ ] Reads `LayoutHints` and passes them to the layout strategy without interpreting geometry
- [ ] No provider vocabulary is hardcoded in this repository — enforced by a test

### Intermediate representation
- [ ] `ConvertTo-PSDrawIOIR` produces an IR from a provider graph
- [ ] Every IR node `Id` is provider-qualified as `Provider:Type:Name`
- [ ] An IR edge whose `From` or `To` names a node absent from the IR is rejected, not dropped
- [ ] IR crosses module boundaries as `PSCustomObject` with a `PSTypeName`, not a class instance
- [ ] IR round-trips through JSON to an equivalent object, compared structurally

### Layout
- [ ] Layout is invoked through a named strategy interface, not a hardcoded call
- [ ] One built-in strategy ships and assigns coordinates to every vertex
- [ ] A test double strategy can be substituted, proving the seam is real
- [ ] Every emitted vertex has non-zero `width` and `height`
- [ ] No two sibling vertices overlap after layout
- [ ] Child vertices of a group carry coordinates relative to the parent
- [ ] Zero geometry constants appear outside the layout pass — enforced by a test

### Emission
- [ ] `Export-PSDrawIODiagram` writes a `.drawio` file from an IR
- [ ] Output contains `<mxCell id="0"/>` and `<mxCell id="1" parent="0"/>`
- [ ] Output is uncompressed XML
- [ ] Output contains no XML comments — enforced by a test
- [ ] Cell ids are unique within a diagram
- [ ] `vertex="1"` and `edge="1"` never appear on the same cell
- [ ] HTML in a `value` is XML-escaped
- [ ] A non-rectangular shape emits a matching `perimeter=` value

### Correctness gates
- [ ] Every emission is validated against `mxfile.xsd` in-process via `XmlSchemaSet`
- [ ] Emission that fails schema validation throws, naming the violation
- [ ] `parse → emit → parse` is stable for a file Core wrote
- [ ] `parse → emit → parse` is stable for a hand-edited file Core did not write
- [ ] Unknown attributes encountered on read are preserved and re-emitted
- [ ] A golden-file corpus exists and a change to any golden file fails the suite

### Proof
- [ ] Renders `PS.DrawIO.Provider.PowerShell`'s graph of itself, end to end, to a file that opens in draw.io
- [ ] The rendered file is not a pile at the origin — asserted, not eyeballed
- [ ] A deliberately malformed IR is rejected with a message naming the offending node

### Quality gates
- [ ] Pester 5 green on Windows and Linux — PowerShell 7+
- [ ] Coverage ≥ 90% on `src/Public`, ≥ 80% overall
- [ ] `PSScriptAnalyzer` clean at Error and Warning; suppressions justified inline
- [ ] `Test-ModuleManifest` passes
- [ ] Imports clean in a fresh session
- [ ] No `src/Public` function exceeds 100 lines
- [ ] All exported names use approved verbs

### Documentation
- [ ] `README.md` — install → resolve → render in under 20 lines
- [ ] `docs/IR-SCHEMA.md` — the intermediate representation
- [ ] `docs/LIMITATIONS.md` — what the built-in layout strategy does not do
- [ ] `CHANGELOG.md` per Keep a Changelog

### Explicitly NOT in v1
- ✗ Multi-provider graph composition — see §3 and Registry ADR 0003
- ✗ The draw.io Desktop CLI layout strategy
- ✗ The `#create` URL back-end
- ✗ The `.drawio.ps1` DSL
- ✗ A theme engine beyond applying declared defaults
- ✗ A good layout algorithm — v1 ships a defined one, not a pretty one
- ✗ PSGallery publication
- ✗ macOS testing

---

## 10. Repository layout

```
   PS.DrawIO.Core/
   ├── src/
   │   ├── PS.DrawIO.Core.psd1          manifest (source of truth for version)
   │   ├── Public/                      one function per file, exported
   │   ├── Private/                     one function per file, internal
   │   ├── Classes/                     PS classes, load-order sensitive, internal
   │   └── en-US/                       help
   ├── tests/
   │   ├── Unit/                        mirrors src/ structure
   │   ├── Integration/                 registry + multi-pass scenarios
   │   ├── Acceptance/                  checkbox-backed; meta-test enforced
   │   └── Fixtures/                    graphs, golden XML, hostile inputs
   ├── docs/
   │   ├── DECISIONS/                   ADRs, numbered, append-only
   │   ├── COMPOSITION-SIGNALS.md       append-only composition evidence
   │   └── SIGNOFF.json                 manual sign-off record
   ├── build/
   │   └── build.ps1                    clean → analyze → test → package
   ├── .agent/                          agent protocol (TRAPS.md; EXECUTION.md gitignored)
   ├── DoNotModify/                     ◄── OFF LIMITS. See AGENTS.md.
   ├── AGENTS.md
   ├── README.md
   ├── CHANGELOG.md
   └── CORE.md                          this file
```

The `.psm1` holds **no logic** — dot-source `Classes` → `Private` → `Public`, then `Export-ModuleMember`. One function per file; filename matches function name. Public functions are exported; private ones are not. Nothing else decides visibility.

Node Ids Core materializes are provider-qualified: `Provider:Type:Name` (ADR 0001).

---

## 11. Design decisions worth remembering

Recorded here because the reasoning is easy to lose and expensive to rediscover.

**Geometry is not optional.** Files open at stored coordinates. Layout strategy may change; the obligation to produce coordinates (or an explicit alternate artifact such as a `#create` URL) does not.

**Hints are intent, never placement.** Providers say "stack these"; Core picks pixels or delegates to a registered strategy. The moment providers encode x/y, every layout backend is coupled to one domain's assumptions.

**Theme before layout.** Font and padding change measured size; size changes geometry. Reordering those passes is a defect, not a style choice.

**Preserve what you do not understand.** Round-trip must keep unknown attributes. Core is an editor in the pipeline, not a filter that normalizes away GUI work.

**XSD is a gate, not a linter you run sometimes.** Emission that skips schema validation is not a successful emission.

**Composition is undecided — treat silence as a stop sign.** Registry ADR 0003 Decision 5 and Core ADR 0001 together mean: qualify Ids, render one graph, log signals, do not invent a join layer in this repository without an ADR and an explicit request.

**Do not invent draw.io XML behavior.** Style Reference, `xml-reference.md`, and `mxfile.xsd` are authoritative. Uncertainty is reported, not papered over.

**No third-party runtime module dependencies** without explicit approval. Prefer built-ins (including in-process XSD via `System.Xml.Schema`).

**PowerShell 7+ only.** No Windows PowerShell 5.1 compatibility shims.

**PSCustomObject + `PSTypeName` at module boundaries;** PS classes internal. Class identity does not safely cross sessions the way duck-typed objects do.

**Never run `Invoke-Pester -CI` in an interactive or agent terminal.** Use `-PassThru` and inspect `FailedCount` / container results. `$LASTEXITCODE` is not how Pester reports failure.

**`/DoNotModify` is off limits.** Read-only. No workarounds, no copied-and-edited substitutes.

**One module, Definition of Done as the bar.** When §9 is written, nothing outside it is required for v1; nothing on an "explicitly not v1" list is built "just in case."

**Fresh session verification.** Prove Core in a session that does not already have other PS.DrawIO modules loaded unless the scenario explicitly requires Registry.

---

## 12. Order of operations (ecosystem)

```
   Registry v1          contract frozen; resolve shapes by (Provider, Type)
        │
        ▼
   Provider.* v1        domain graphs (no .drawio)
        │
        ▼
   THIS REPO            IR + layout passes + XML + gates
        │
        ▼
   Provider adapters    domain graph → IR
        │
        ▼
   DSL (later)          .drawio.ps1 front-end into the same pipeline
```

Core does not implement providers. Core does not publish the contract. Core does not compose multi-provider estates in v1.
