# ADR 0001: Provider-qualified node Ids

## Status
Accepted (cheap hedge; composition ownership undecided)

## Context
Providers emit closed graphs with node Ids meaningful inside one provider
boundary (for example PowerShell `Function:Get-Thing`). Registry contract v1
resolves shapes by a single `(Provider, Type)` pair and does not join graphs.

Registry ADR 0003 Decision 5 leaves multi-provider composition ownership open:

> Nothing in any current specification describes a component that composes
> multiple providers' graphs. `REGISTRY.md` §4 assigns Core geometry and XML
> emission, which does not include composition. Therefore either Core's scope
> expands or a component is missing; that choice is not made here.

— `PS.DrawIO.Registry` `docs/DECISIONS/0003-cross-provider-references.md`

If Core (or a future composition layer) ever merges nodes from more than one
provider, bare per-provider Ids collide. Choosing a stable Id shape early is
cheap; choosing composition ownership is not.

## Decision
Every node Id in Core's intermediate representation carries the owning
provider. Shape:

```
Provider:Type:Name
```

Example: `PowerShell:Function:Get-Thing` — not `Function:Get-Thing`.

- `Provider` is the registered provider name (PascalCase, no dots).
- `Type` is the semantic type key used with the registry (`Resolve-PSDrawIOShape -Type`).
- `Name` is the provider-local identity string.

This ADR does **not** decide who composes multi-provider graphs, whether Core
gains a join API, or how foreign-provider edges are declared. It only fixes Id
shape so a future join does not require rewriting every node key.

## Consequences
- Qualified Ids cost nothing today: Core renders one provider's graph at a
  time, so the prefix is unused for disambiguation in the single-provider path.
- They are close to impossible to retrofit once diagrams exist that depend on
  the Id format (links, stable cell ids, golden fixtures, external tools).
- This is a **cheap hedge against a decision not yet made** — **not** a
  commitment to building multi-provider composition. A future reader must not
  treat qualification as proof that composition was decided, and must not
  delete the qualification as "unused."
- Providers may keep internal Ids; Core normalizes at the boundary it owns.
- Cross-provider edge semantics, ownership fields, and join APIs remain out of
  scope until a later ADR (and likely a contract major if the registry grows).
