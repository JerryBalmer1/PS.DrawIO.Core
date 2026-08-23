# ADR 0004: Acceptance suite tests Core in isolation

## Status
Accepted

## Context
Core's acceptance harness loads only this module. `Assert-CoreModuleAvailable`
imports `PS.DrawIO.Core` and nothing else:

```powershell
function Assert-CoreModuleAvailable {
    $manifest = Get-CoreManifestPath
    Test-Path -LiteralPath $manifest | Should -BeTrue -Because 'src/PS.DrawIO.Core.psd1 must exist'
    Import-Module $manifest -Force
}
```

CORE.md §9 **Contract consumption** includes checkboxes that describe behaviour
at the Core / registry boundary. Two of them, by label, are:

- `Resolves a semantic type through PS.DrawIO.Registry and applies the returned style`
  (rewritten under this decision to an injected-resolver seam; see Decision)
- `Fails loudly when a semantic type is not registered, naming the type and provider`

Those labels describe integration behaviour, but they live in an acceptance
suite that runs Core alone. The pre-rewrite bodies made that mismatch concrete:

```powershell
It (Get-Label 'Resolves a semantic type') -Tag Acceptance {
    Assert-CoreModuleAvailable
    $graph = Get-AcceptanceProviderGraph
    $ir = ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider
    $ir | Should -Not -BeNullOrEmpty
    $styled = @($ir.Nodes | Where-Object { $_.Style -or $_.ResolvedStyle -or $_.ShapeStyle })
    $styled.Count | Should -BeGreaterThan 0 -Because 'Core must resolve semantic types through Registry and apply returned style'
}

It (Get-Label 'Fails loudly when a semantic type') -Tag Acceptance {
    Assert-CoreModuleAvailable
    $graph = Get-AcceptanceProviderGraph
    $graph.Nodes[0].Type = 'DefinitelyNotRegisteredTypeZZZ'
    { ConvertTo-PSDrawIOIR -Graph $graph -Provider $graph.Provider -ErrorAction Stop } |
        Should -Throw -Because 'unregistered semantic types must fail loudly'
    # ...
}
```

The first body assumed a live registry resolve and a declaration that carries
style. The suite never loads `PS.DrawIO.Registry` and never registers a
provider, so that assumption cannot hold inside acceptance.

The provider gap recorded in
`PS.DrawIO.Provider.PowerShell/docs/PATTERNS.md` compounds it: even with the
registry loaded, PowerShell shape declarations carry no `Style`, so a
successful resolve still returns nothing to apply. That is a provider content
problem, not a Core acceptance concern.

## Decision
1. Core's acceptance suite continues to test **Core in isolation**. It does
   not gain a registry dependency, a sibling checkout, or a provider
   registration step.
2. Checkboxes that describe behaviour at the Core / registry boundary assert
   the **seam** — that Core calls a resolver and applies whatever declaration
   is returned — not the content of any provider's declaration.
3. Content correctness (whether a real provider's shapes carry `Style`,
   `LinkTemplate`, and so on) is an integration concern and belongs in a
   future integration suite, not here.
4. The §9 style checkbox is rewritten so it is satisfiable with an injected
   resolver double and does not name `PS.DrawIO.Registry`. The "fails loudly
   when unregistered" checkbox stays as written; it remains satisfiable once
   Core's seam rejects unknown types without a live registry module.

## Consequences
- The Contract consumption checkbox that formerly required a live registry
  style resolve changes meaning: it now proves the injected-resolver seam and
  application of returned declaration content (including "no Style means no
  invented style"), not end-to-end registry + provider styling.
- Core **cannot** prove end-to-end styling on its own. That is deliberate.
  End-to-end styling needs a registered provider with style-bearing
  declarations and belongs outside this acceptance suite.
- The two §9 **Proof** checkboxes that need a real provider graph through
  Core remain blocked for a separate reason recorded in ADR 0003 (identity at
  the IR boundary is decided; remaining Proof work is Export / layout /
  emission and the eventual adapter caller, not acceptance loading Registry).
- Acceptance stays free of a runtime dependency on `PS.DrawIO.Registry`.
