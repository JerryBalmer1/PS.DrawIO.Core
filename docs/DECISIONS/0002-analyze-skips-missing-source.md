# ADR 0002: Analyze skips missing source

## Status
Accepted (temporary; remove when src/ exists)

## Context
CI run #2 on `PS.DrawIO.Core` failed on **both** `windows-latest` and
`ubuntu-latest` for a reason that was not the intended signal:

```
Invoke-ScriptAnalyzer: Cannot find path '.../PS.DrawIO.Core/src'
because it does not exist.
Error: Process completed with exit code 1.
```

The default `All` task order is fixed: Clean → Analyze → Test → Package.
Analyze targeted `src/`, which does not exist yet (Core has `CORE.md` and a
harness, not module source). The build died in Analyze, so Test never ran.

Test **should** fail today: `CORE.md` §9 is a deliberate owner-authored
placeholder with zero checkboxes, and the acceptance meta-test requires a
non-empty label list whenever `CORE.md` exists. That informative failure was
masked by a stale path error. Red CI for the wrong reason is how a real
regression hides.

The fixed pipeline order assumes a repository that already has source. This
one does not yet. The same structural collision — a pipeline that must fail on
failure, in a repository that legitimately has one — is recorded in
`PS.DrawIO.Provider.PowerShell` ADR 0004:

> Both behaviours are individually correct. The collision is the problem.
>
> … CI is red on every run for the same single label. Exit code alone cannot
> distinguish a new regression from the known state. A human must read the
> failing test name.

— `PS.DrawIO.Provider.PowerShell` `docs/DECISIONS/0004-deliberate-failure-blocks-packaging.md`

Provider ADR 0004 rejected an expected-failure allowlist and kept the Test
throw. Registry uses the same Clean → Analyze → Test → Package shape. This is
now the **third** repository in the ecosystem to hit a variant of that shape
(Registry structure; Provider deliberate-fail vs Package; Core missing `src/`
vs Analyze). If it recurs a fourth time, the fixed task order itself may be
the defect rather than any individual repository's circumstances.

## Decision
1. **Analyze warns and continues when `src/` is absent.** The warning must
   state explicitly that ScriptAnalyzer did **not** run and that the skip is
   temporary until `src/` exists. Use `Write-Warning`, never `Write-Host`.
2. **When `src/` exists, behaviour is unchanged:** run
   `Invoke-ScriptAnalyzer` at Error and Warning severity and throw on any
   finding.
3. **The branch is temporary.** A comment in `build/build.ps1` and this ADR
   require deletion the moment `src/` lands. Removal condition: the first
   commit that creates `src/`.
4. **Do not add an expected-failure allowlist.** Provider ADR 0004 rejects
   that mechanism; this ADR does not reverse it. The meta-test remains a real
   failure until the owner writes §9 checkboxes.
5. **Do not give Package the same treatment.** Failing on a missing manifest
   when packaging is correct and is not masking a later intentional signal
   today.

## Consequences
- While the branch exists, the analyzer gate is **inert** for Core: CI cannot
  detect an analyzer regression in module source that is not there yet.
- After this change, the default pipeline reaches Test. The visible CI failure
  becomes the meta-test (empty §9), which is the **intended** signal until the
  owner writes the Definition of Done.
- Operators must not treat "Analyze succeeded" as "source was clean" while
  `src/` is missing — read the warning.
- **Remove this ADR's build branch** in the same change that introduces `src/`.
  Leaving the skip after source exists would recreate the cannot-fail path
  this project has already paid for elsewhere.

## Resolution
Condition met: first change that creates `src/` (IR implementation; working tree
on 2026-08-22, not yet committed at write time).

The temporary missing-`src/` branch in `build/build.ps1` was deleted in that
same change. Analyze again runs `Invoke-ScriptAnalyzer` unconditionally against
`src/` and throws on any Error or Warning finding. The analyzer gate is live.
