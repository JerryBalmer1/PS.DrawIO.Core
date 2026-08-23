# Intermediate representation (IR)

What Core actually builds and consumes. Derived from `src/`, not from intention.

Providers speak domain graphs. Core speaks **diagram-shaped** IR: nodes, edges,
opaque style strings, optional geometry, and enough metadata to emit mxfile XML.
The IR is not a `PSModuleGraph`, not Terraform state, and not draw.io XML.

Entry point: `ConvertTo-PSDrawIOIR`. Layout: `Invoke-PSDrawIOLayout` /
`Invoke-PSDrawIOBuiltinLayout`. Import: `ConvertFrom-PSDrawIODiagramXml`.
Emission: `ConvertTo-PSDrawIODiagramXml` → `Export-PSDrawIODiagram`.

---

## Boundary type

Every IR root, node, and edge is a **`PSCustomObject`** with a `PSTypeName`
stamped via the constructor hashtable key (which becomes
`$obj.PSObject.TypeNames[0]`, not a note property):

| Object | PSTypeName |
|---|---|
| Root | `PS.DrawIO.IR` |
| Node | `PS.DrawIO.IR.Node` |
| Edge | `PS.DrawIO.IR.Edge` |

No public IR class instances cross the module boundary. Class identity is tied
to the defining module session and does not safely cross sessions the way
duck-typed objects do (`CORE.md` §10; same reason Registry uses PSCustomObject
at its boundary).

`ConvertTo-Json` does **not** serialize `PSTypeName` / `TypeNames`. Structural
JSON round-trip compares note properties; type names are re-applied by code
that rebuilds IR, or checked on live objects.

---

## Root object (`PS.DrawIO.IR`)

Produced by `ConvertTo-PSDrawIOIR` (`src/Public/ConvertTo-PSDrawIOIR.ps1`).

| Field | Type | Always present after convert? | Set by |
|---|---|---|---|
| `Provider` | `string` | yes | caller `-Provider` (mandatory; PascalCase `^[A-Z][A-Za-z0-9]+$`) |
| `Nodes` | `object[]` | yes (may be empty) | `ConvertTo-PSDrawIOIRContent` |
| `Edges` | `object[]` | yes (may be empty) | `ConvertTo-PSDrawIOIRContent` |
| `LayoutHints` | `object[]` | yes (default `@()`) | copied from graph if present |
| `LinkTemplate` | `object` / `$null` | yes (may be `$null`) | copied from graph if present |
| `Metadata` | `PSCustomObject` | **no** on convert path | **import only** — mxfile / diagram / model attribute bags |

Optional graph.Provider, when set and non-whitespace, must match `-Provider`
(ordinal case-sensitive) or convert throws.

Optional `-Resolver` is an injected seam (ADR 0004). Core never loads
`PS.DrawIO.Registry`. When supplied, each node/edge type is resolved once and
declaration fields are copied onto the IR member (see Style below). Omitting
`-Resolver` skips resolution and invents no style.

---

## Node (`PS.DrawIO.IR.Node`)

### Fields after `ConvertTo-PSDrawIOIR`

From `ConvertTo-PSDrawIOIRNode`:

| Field | Type | Always present? | Notes |
|---|---|---|---|
| `Id` | `string` | yes | Provider-qualified when Core materializes (below) |
| `Provider` | `string` | yes | Same as root `-Provider` |
| `Type` | `string` / `$null` | yes | From node.Type, else middle segment of qualified Id |
| `Name` | `string` / `$null` | yes | From node.Name, else last segment of qualified Id |
| `Label` | any | yes (may be `$null`) | Display text; emission uses Label, else Name, else Id |
| `ParentId` | any / `$null` | yes | Group parent node Id when nested |
| `Link` | any / `$null` | yes | Explicit URL / `vscode://` target when set |
| `Variant` | any / `$null` | yes | From `Variant`, else provider `Visibility` mapped onto Variant |
| `IsGroup` | `bool` | yes | Default `$false` |
| `Metadata` | `PSCustomObject` | yes | Catch-all: unknown node properties + nested `Metadata` bag |

**Not present after convert alone:** `X`, `Y`, `Width`, `Height`, nested
`Geometry`, `Style`, `ResolvedStyle`. Geometry is absent until layout runs —
acceptance asserts that; it is load-bearing. Style appears only when a
`-Resolver` returns a declaration with `Style` (`Add-PSDrawIOResolvedDeclaration`
writes both `Style` and `ResolvedStyle` to the same string).

Extra provider properties that are not the reserved set
(`PSTypeName`, `Id`, `Type`, `Name`, `Label`, `Visibility`, `Variant`,
`ParentId`, `Link`, `IsGroup`, `Metadata`) are folded into `Metadata`.

### Fields layout adds

`Invoke-PSDrawIOBuiltinLayout` mutates vertices in place with flat doubles:

| Field | Type | When |
|---|---|---|
| `X` | `double` | every vertex (not `IsEdge` / `Edge` nodes) |
| `Y` | `double` | same |
| `Width` | `double` | same (groups may be sized from children first) |
| `Height` | `double` | same |

There is **no** nested `Geometry` object on the convert or layout path.
Emission (`ConvertTo-PSDrawIODiagramXml`) accepts **either** flat `X`/`Y`/
`Width`/`Height` **or** a nested `Geometry` with those names — defensive
read for hand-built IR. Layout never writes the nested form.

`LayoutHints` with `Kind = 'Stack'` and `Targets` (node Ids) only reorder
vertices; unknown hint kinds are ignored. Children whose `ParentId` resolves
to a node in the same IR are placed relative to the parent origin.

### Fields import adds

`ConvertFrom-PSDrawIODiagramXml` builds the same PSTypeName and core fields,
then attaches geometry and style from the file:

| Field | Source |
|---|---|
| `Id` | mxCell `id`, or UserObject `id` when the nested cell omits id |
| `Provider` / `Type` / `Name` / `Variant` | always `$null` on import |
| `Label` | cell `value`, or UserObject `label` |
| `Link` | UserObject / object `link` |
| `ParentId` | cell `parent` when not `1` |
| `IsGroup` | style contains a `group` token |
| `Style` | cell `style` (missing vertex style → `whiteSpace=wrap;html=1;`) |
| `X` `Y` `Width` `Height` | mxGeometry attributes (may be `$null`) |
| `Metadata.XmlAttributes` | unknown attrs from bare mxCell **and** UserObject customs, merged |

Import does **not** force `Provider:Type:Name` qualification. Bare ids such as
`hand-1` remain bare. ADR 0001 governs ids **Core generates**, not ids Core
reads. Emission likewise does not reject unqualified ids on re-emit.

Root import also sets `Metadata.MxFileAttributes` /
`DiagramAttributes` / `ModelAttributes` for wrapper round-trip.

---

## Edge (`PS.DrawIO.IR.Edge`)

### Fields after `ConvertTo-PSDrawIOIR`

From `ConvertTo-PSDrawIOIREdge`:

| Field | Type | Always present? | Notes |
|---|---|---|---|
| `Id` | `string` | yes | Provider `Edge.Id` if set; else `edge:{index}:{From}:{To}:{Type}` |
| `From` | `string` | yes | **Node Id**, never a display name |
| `To` | `string` | yes | **Node Id**, never a display name |
| `Type` | `string` | yes | Semantic edge kind (may be empty string on import) |
| `Aggregates` | object / `$null` | yes | From `Aggregates`, or synthesized from `CallCount` + `Extents` |

`From` and `To` must each name an Id present in the IR node set. Missing ends
are a terminating error naming the offending edge — never silently dropped
(`ConvertTo-PSDrawIOIRContent`; same check on emit).

With `-Resolver`, edge `Type` may receive `Style` / `ResolvedStyle` the same
way nodes do.

### Fields import / emit use beyond convert

| Field | Role |
|---|---|
| `Style` / `ResolvedStyle` | Opaque stroke/arrow string; emit prefers ResolvedStyle, then Style, else `endArrow=classic;html=1;rounded=0;` |
| `Link` | Optional; triggers UserObject wrap on emit |
| `Metadata.XmlAttributes` | Preserved unknown attributes |
| `Metadata.Parent` | Non-default edge parent cell |
| `Metadata.Value` | Edge label text |
| `Metadata.GeometryRelative` | Import-only geometry flag |

**No waypoints.** The route pass is not implemented; emit always writes
`mxGeometry relative="1"` for edges. `CORE.md` §4 lists “Waypoints / routing
data” as an IR concern — **code does not carry them today**.

---

## Node Ids

Shape Core materializes (`Resolve-PSDrawIOQualifiedId`, ADR 0001):

```text
Provider:Type:Name
```

Example: `Demo:Widget:Get-Foo`.

- If `Node.Id` already matches `^[^:]+:[^:]+:.+$`, it is kept as-is.
- Otherwise `Type` and `Name` are required and Id becomes
  `'{Provider}:{Type}:{Name}'`.
- Duplicate Ids after qualification throw.

ADR 0001 is a **cheap hedge** against a future multi-provider join, not proof
that composition was decided. Core still renders **one provider graph at a
time** (`CORE.md` §3; Registry ADR 0003 Decision 5).

Imported / hand-edited diagrams may carry unqualified cell ids. Core does not
rewrite them on read. Emit comments in `ConvertTo-PSDrawIODiagramXml` state
this explicitly.

---

## Style

Style on the IR is an **opaque string**. Core does not interpret draw.io style
semantics beyond:

- preferring `ResolvedStyle`, then `Style`, then `ShapeStyle` on emit
- optional `shape=` / `perimeter=` synthesis from a `Shape` note or
  `Metadata.Shape`
- detecting `group` for `IsGroup` on import and re-adding `group` when
  `IsGroup` is true on emit
- default vertex style `whiteSpace=wrap;html=1;` when nothing else is set

There is no structured theme object on the IR in v1 code paths documented
here. Resolver output is copied field-wise; unknown declaration properties are
ignored (`Add-PSDrawIOResolvedDeclaration`). Geometry is never written by
resolution.

---

## Preserved unknown attributes → UserObject

Import stores non-known cell / UserObject attributes on
`Metadata.XmlAttributes` (one bag for bare-mxCell customs and wrapper customs).

Emit (`ConvertTo-PSDrawIODiagramXml`, ADR 0006 Option A):

- If the cell has a **link** and/or preserved attributes
  (`Metadata.XmlAttributes` or `Metadata.UserObjectAttributes`), wrap in
  `<UserObject id="..." label="...">` (plus `link` when set).
- Custom attributes are applied on the **UserObject**, not on the bare
  `mxCell` (mxCell has no `xs:anyAttribute` in the vendored schema).
- Nested `mxCell` keeps its own `id` (schema dual-id; tests assert mxCell ids).
- Cells with neither link nor preserved attrs stay a bare `mxCell`.

Known cell attrs stripped on import (not preserved as customs):
`id`, `value`, `style`, `vertex`, `edge`, `parent`, `source`, `target`.
Known UserObject attrs not treated as customs: `label`, `link`, `id`.

---

## Closed graph

Provider graphs feeding convert must be closed: every edge end names a node Id
in that graph. Placeholders for external / unresolved ends are the provider’s
job. Core rejects open ends at convert and again at emit.

---

## What the IR does **not** carry

- Provider domain vocabulary (`PSFunction`, AST extents as first-class IR
  types, Terraform resource addresses as typed nodes, …). Those stay in the
  provider graph; only what convert maps appears on the IR.
- Raw draw.io / mxfile XML strings as the working form (import produces IR;
  emit consumes IR).
- Draw.io style semantics beyond an opaque resolved style string (and the
  small emit helpers above).
- Multi-provider composition, join, or overlay — out of scope for v1
  (`CORE.md` §3; Registry ADR 0003 Decision 5). Record signals in
  `docs/COMPOSITION-SIGNALS.md`; do not invent ownership in this schema.
- Waypoints / edge routing data (spec mentions them; layout/emit do not).
- Nested `Geometry` objects on the convert→layout happy path (flat X/Y/W/H
  only).

---

## CORE.md §4 vs code (divergences)

Document the code; note the gap.

| CORE.md §4 | Code |
|---|---|
| Node `Geometry` as `x,y,width,height` object | Layout writes flat `X`,`Y`,`Width`,`Height`. Emit accepts either. |
| Node / edge `ResolvedStyle` after resolve + theme | Resolver copies declaration `Style` → both `Style` and `ResolvedStyle`. No separate theme pass mutates IR style today. |
| Edge `Waypoints` / routing data after route pass | No route pass; no waypoint fields; edges emit `relative="1"` geometry only. |
| “Every IR node Id is provider-qualified” | True for Ids **Core materializes** via convert. **False** for import: unqualified ids are preserved (ADR 0001 scope). |
| Edge `From`/`To` “qualified” | Convert requires ends ∈ node Id set; qualification of those Ids is whatever the nodes carry. Import may yield bare ends matching bare node ids. |

---

## Worked example (real run)

Command (fresh session, module loaded from `./src`):

```powershell
$graph = [pscustomobject]@{
    Nodes = @(
        [pscustomobject]@{ Type = 'Widget'; Name = 'Get-Foo'; Label = 'Get-Foo' }
        [pscustomobject]@{ Type = 'Widget'; Name = 'Set-Foo'; Label = 'Set-Foo' }
    )
    Edges = @(
        [pscustomobject]@{
            From = 'Demo:Widget:Get-Foo'
            To   = 'Demo:Widget:Set-Foo'
            Type = 'Link'
        }
    )
}
$ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider Demo
$ir | ConvertTo-Json -Depth 8
```

Verbatim `ConvertTo-Json` output from that run (2026-08-23). Live object
type names were `PS.DrawIO.IR` / `PS.DrawIO.IR.Node` / `PS.DrawIO.IR.Edge`
via `PSObject.TypeNames` (not present in JSON). Pre-layout:
`Nodes[0]` had no `X` property.

```json
{
  "Provider": "Demo",
  "Nodes": [
    {
      "Id": "Demo:Widget:Get-Foo",
      "Provider": "Demo",
      "Type": "Widget",
      "Name": "Get-Foo",
      "Label": "Get-Foo",
      "ParentId": null,
      "Link": null,
      "Variant": null,
      "IsGroup": false,
      "Metadata": {}
    },
    {
      "Id": "Demo:Widget:Set-Foo",
      "Provider": "Demo",
      "Type": "Widget",
      "Name": "Set-Foo",
      "Label": "Set-Foo",
      "ParentId": null,
      "Link": null,
      "Variant": null,
      "IsGroup": false,
      "Metadata": {}
    }
  ],
  "Edges": [
    {
      "Id": "edge:0:Demo:Widget:Get-Foo:Demo:Widget:Set-Foo:Link",
      "From": "Demo:Widget:Get-Foo",
      "To": "Demo:Widget:Set-Foo",
      "Type": "Link",
      "Aggregates": null
    }
  ],
  "LayoutHints": [],
  "LinkTemplate": null
}
```
