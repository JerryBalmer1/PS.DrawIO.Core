# TRAPS.md — hard-won failure facts

Read this file **once** at the start of every agent task, before any command.

This is the accumulated cost of real mistakes in the PS.DrawIO project. Entries
are facts about tools, shells, and test runners — not excuses for skipping work.

**Append-only.** Never edit an existing entry to make a task pass. Never delete.
If a fact is wrong, add a superseding entry that says so.

---

## How to add an entry

1. Take the next sequential id (`T-012`, …).
2. Symptom first (what you saw).
3. Cause second (what was actually true).
4. Fix third (what to do next time).
5. Add only when something actually cost time.

---

## Entries

### T-001 — Terminal shows `>>` and stops responding

**Symptom:** The interactive shell prints `>>` and ignores further input as if hung.

**Cause:** PowerShell is in continuation mode from an unclosed quote or
here-string. The terminal is not stuck; the parser is. Further multi-line
commands make it worse.

**Fix:** Abandon the terminal, start a new one. Never send `exit` or blank
lines. Prevent by never sending multi-line PowerShell interactively — write a
`.ps1` and run `pwsh -NoProfile -File <path>`.

### T-002 — File content becomes the literal text `System.Xml.XmlDocument`

**Symptom:** A file that should hold XML or script text contains only
`System.Xml.XmlDocument`.

**Cause:** `Set-Content` or `Out-File` received an object, not a string, and
wrote `.ToString()`. Nothing overwrote the file. No file watcher exists.

**Fix:** Use `$xml.OuterXml`, or `$xml.Save($path)`. Always pass a string to
file writers.

### T-003 — `Invoke-Pester -CI` terminates the session

**Symptom:** The host process exits after Pester finishes (or mid-run).

**Cause:** `-CI` sets `Run.Exit`, which exits the host process.

**Fix:** Use `-PassThru`, then inspect `FailedCount` and `Containers.Result`.

### T-004 — `$LASTEXITCODE` does not reflect Pester results

**Symptom:** After `Invoke-Pester`, `$LASTEXITCODE` is 0 (or stale) despite
failures.

**Cause:** `$LASTEXITCODE` is set by native executables, not by PowerShell
cmdlets.

**Fix:** Inspect the `PassThru` result object (`FailedCount`, etc.).

### T-005 — Pester 5 discovery and run are separate scopes

**Symptom:** File-scope variables read inside `BeforeAll` or `It` arrive null.

**Cause:** Pester 5 re-executes the file; discovery and run are distinct scopes.
Bare assignments at file scope are not the same as `$script:`-scoped values
visible in blocks.

**Fix:** Use the `$script:` prefix for values shared across discovery helpers
and run-time blocks. For values that must survive discovery→run re-exec, use a
documented durable store (see project acceptance patterns).

### T-006 — `@($null).Count` is 1

**Symptom:** A non-emptiness check passes for an absent property.

**Cause:** `@($null).Count` is `1`. This let a conformance suite pass for
manifests with no `Capabilities` at all.

**Fix:** Assert property presence separately from content.

### T-007 — A commit cannot contain its own hash

**Symptom:** A sign-off test that requires `Commit -eq HEAD` can never stay
green after the sign-off commit lands.

**Cause:** Committing the sign-off file changes HEAD; the recorded hash cannot
equal the commit that contains it.

**Fix:** Record an ancestor commit plus a drift check instead of equality to
HEAD.

### T-008 — Pester 5 `Container.Tests` is null after a run

**Symptom:** Counting tests via `Container.Tests` throws or returns nothing.

**Cause:** After a run, `Container.Tests` is not reliably populated.

**Fix:** Use `TotalCount` to count tests in a container.

### T-009 — Unpinned `Install-Module` installs a different version in CI than locally

**Symptom:** CI fails on Pester parameter sets that work locally (or the reverse).

**Cause:** Unpinned `Install-Module` can install Pester 6+, which removed the
legacy `-CodeCoverage` parameter set.

**Fix:** Pin a maximum version of Pester (and other build modules) in CI and
local bootstrap.

### T-010 — git does not track empty directories

**Symptom:** A loader that enumerates a directory works locally but fails on a
fresh clone.

**Cause:** git does not track empty directories. Deleting the last file in a
tracked directory removes the directory from the tree.

**Fix:** Keep a tracked placeholder (or ensure the loader tolerates a missing
directory) before relying on the path existing after clone.

### T-011 — `-Severity` filters findings, not rules

**Symptom:** A rule you thought was disabled still runs (or still costs time)
under `Invoke-ScriptAnalyzer -Severity Error,Warning`.

**Cause:** `-Severity` filters findings, not which rules execute.
`PSUseCorrectCasing` still executes under `-Severity Error,Warning`; only its
output is dropped.

**Fix:** Exclude rules explicitly when you need them not to run; do not assume
severity alone skips rule execution.
