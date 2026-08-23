# ADR 0003: Provider identity at the IR boundary

## Status
Open (no decision made)

## Context
Core ADR 0001 requires every IR node Id to be provider-qualified as
`Provider:Type:Name`. That shape needs a provider name at the moment Core
normalizes a graph into IR.

`ConvertTo-PSDrawIOIR` (working tree, IR slice) reads the inbound graph's
`Provider` property and throws when it is missing or blank:

```
Provider graph must include a non-empty Provider.
```

That check exists so Core can build the qualified Ids ADR 0001 requires. It
assumes the inbound object carries provider identity.

`PS.DrawIO.Provider.PowerShell` documents the real v1 graph shape in
`docs/DOMAIN-MODEL.md`. Top-level fields of `PSModuleGraph` are defined as:

> `PSModuleGraph` is the v1 output. It contains:
>
> - `Path`: analyzed file or directory. `RootPath` records the single analysis root.
> - `Nodes`: …
> - `Edges`: …
> - `Analysis.Confidence`: …

No `Provider` field is defined on `PSModuleGraph`. A real
`Build-PSDrawIOPSGraph` result therefore does not satisfy Core's current
inbound requirement. The failure was observed on the CORE.md §9 Proof path
that feeds the provider's graph of itself into Core:

```
RuntimeException: Provider graph must include a non-empty Provider.
```

Acceptance and unit fixtures in Core use a **synthetic** graph
(`PS.DrawIO.ProviderGraph`) that **does** set `Provider` (for example
`PowerShell`). Those fixtures made the mismatch invisible until a real
`PSModuleGraph` was tried.

This is a boundary finding between two repositories that both claim v1
shapes. It is not yet a decision about which side owns the fix.

## Options
No recommendation. Each option is listed with its cost only.

### A. `PSModuleGraph` gains a `Provider` field
The PowerShell provider emits provider identity on every graph.

**Cost:** The provider is at v1.0.0 tagged. Adding a top-level field is a
published-shape change for the first provider and for any consumer already
serializing `PSModuleGraph`. Requires coordinated provider release and doc
updates (`DOMAIN-MODEL.md`, possibly contract/patterns notes). Does not by
itself teach Core anything new if Core already requires the property.

### B. `ConvertTo-PSDrawIOIR` takes `-Provider`
The caller supplies the provider name. The graph need not carry it.

**Cost:** Every caller must know the correct provider string. Nothing in Core
validates that `-Provider` matches the graph's origin; a wrong value yields
plausible, wrong qualified Ids. Shifts identity from data to call-site
discipline. Acceptance fixtures and public examples must pass the parameter
explicitly.

### C. The v1.1 IR adapter supplies it
`PROVIDER.md` §8 already schedules a thin v1.1 adapter that maps
`PSModuleGraph` onto Core's IR. That adapter could inject provider identity.

**Cost:** Core cannot render a real provider graph end-to-end until that
adapter exists and is used on the path into Core. The §9 Proof checkboxes that
depend on a real PowerShell self-graph stay blocked on a future provider
deliverable rather than on Core alone. Core's current throw remains correct
against bare `PSModuleGraph` until then.

## Consequences
Until this ADR is decided (and the chosen option is implemented), the
following CORE.md §9 **Proof** checkboxes that require a real provider graph
through Core remain blocked:

- Renders `PS.DrawIO.Provider.PowerShell`'s graph of itself, end to end, to a file that opens in draw.io
- The rendered file is not a pile at the origin — asserted, not eyeballed

Other Proof items that do not depend on a live `PSModuleGraph` (for example a
deliberately malformed IR rejected by name) are outside this blockage unless
they are later wired through the same real-graph path.

Status remains **Open**. This document does not choose A, B, or C and does
not authorize implementation of any option.
