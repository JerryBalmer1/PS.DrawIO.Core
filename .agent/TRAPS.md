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

### T-012 — Acceptance It passes while only asserting half of its checkbox label

**Symptom:** An acceptance test is green even though a component named in the
checkbox label does not exist yet. Example: "Reads LayoutHints and passes them
to the layout strategy without interpreting geometry" passed with no layout
strategy in the module — the body only required non-empty `IR.LayoutHints` and
conditionally required `Invoke-PSDrawIOLayout` if convert had already stamped
geometry.

**Cause:** The label bundles two (or more) claims with "and", or names a
component that does not exist yet. The second claim is untestable until that
component exists, so the assertion body silently covers only the first half.
Green means "the asserted half holds," not "the full checkbox is done." This is
the eighth cannot-fail-shaped finding in this project: a check that cannot
fail for the reason its name implies.

**Fix:** When a checkbox label contains "and" or names a component that does
not exist yet, state in `EXECUTION.md` which half is actually asserted. A label
that overclaims is a **spec defect**, not a test defect — do not weaken the
test to match the label, and do not treat a green It as proof of the untested
half.

### T-013 — Omitting a mandatory parameter prompts instead of throwing

**Symptom:** A test or agent command that calls a function without a mandatory
parameter appears to hang. The terminal shows `Provider:` (or similar) and
stops. Later commands are swallowed as answers to the prompt. Multiple
terminals look "stuck" after one omission.

**Cause:** Interactive PowerShell prompts for missing mandatory parameters. It
does not throw `ParameterBindingException` unless the host is non-interactive.
Pester in an interactive agent terminal inherits that behavior. One prompt can
consume subsequent tool commands as parameter values.

**Fix:** Never invoke a function without its mandatory parameters to "prove"
binding. Assert parameter metadata instead:

```powershell
$p = (Get-Command Foo).Parameters['Bar']
$attr = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
$attr.Mandatory | Should -BeTrue
```

Always run agent PowerShell as `pwsh -NoProfile -NonInteractive -File <path>`.
Under `-NonInteractive`, missing mandatory parameters become binding errors.

### T-014 — Two-attempt rule counts symptoms, not intentions

**Symptom:** An agent burns many terminals and "attempts" on what looks like
separate failures (empty returns, hung shells, ignored commands), then keeps
retrying past the two-attempt limit.

**Cause:** The two-attempt rule is about the **same symptom** twice, not about
distinct planned steps. One mandatory-parameter prompt (T-013) can present as
many stuck terminals. Counting each stuck shell as a new attempt hides that
the underlying failure already happened twice.

**Fix:** When the same symptom recurs (prompt hang, `>>` continuation, empty
return pair), record it under Blocked after the second occurrence and stop.
Do not open a third terminal to "try a different approach" at the same
symptom. Check `TRAPS.md` before forming a new hypothesis.

### T-015 — Broad error-message regex greens a weaker subsystem

**Symptom:** An acceptance test passes while asserting something narrower than
its checkbox label promises, because the assertion regex is broad enough to
match an unrelated error.

**Cause:** An error-message pattern with several alternatives will match errors
from other subsystems. Here, `schema|invalid|violation|mxfile|node` matched an
IR identity error because it contained `node`. This is the same class of
label-overclaim as T-012, but the mechanism is a loose `Should -Match` list
plus a fallback branch that substitutes IR rejection for schema validation
when `Test-PSDrawIODiagramSchema` is absent.

**Fix:** When asserting on an error message, match a phrase specific to the
subsystem under test, not a list of generic words. If a test has a fallback
branch for an unimplemented feature, that branch must fail, not substitute a
weaker assertion.

### T-016 — Incomplete instructions are not a prompt to reconstruct intent

**Symptom:** The instructions received are incomplete — a task list stops
mid-sentence, or references a step whose text is missing.

**Cause:** The chat input truncated the paste. It is not a signal to infer the
rest.

**Fix:** Report the exact point where the text stops and stop working. Do not
reconstruct intent from VS Code's chat database, local files, or prior
transcripts. A guessed instruction that happens to be right is
indistinguishable from one that is wrong until it has already been executed.

### T-017 — Cleanup claimed in the log without verified deletion

**Symptom:** An execution log states that temporary files were deleted, and they
are still present.

**Cause:** The cleanup line was written as part of the report rather than
executed and verified.

**Fix:** Delete temps, then run `git status --short` and paste the raw output
into the log as proof. A cleanup claim without that output is a claim, not a
fact.

### T-018 — DoD checkbox fails only after substantial implementation

**Symptom:** A Definition-of-Done checkbox cannot be made to pass, and this is
only discovered after substantial implementation effort.

**Cause:** The checkbox assumed an artifact or an integration that does not
exist. A checkbox is a claim about the world; implementing one without
checking the claim first is building on an assumption.

**Fix:** Run the feasibility pass in `AGENTS.md` before writing code. Name the
failing input, list every artifact the test needs, and stop if any dependency
lives in another repository.

### T-019 — Recorded trap hit repeatedly and treated as new each time

**Symptom:** A trap recorded in this file is hit repeatedly during a single run
and treated as a new problem each time.

**Cause:** `TRAPS.md` was read at task start and not consulted again when
something failed. Reading is not applying.

**Fix:** When a command fails, check `TRAPS.md` BEFORE forming a hypothesis. If
the symptom is there, cite the trap ID in `EXECUTION.md` and apply the stated
fix. If you cite the same ID twice in one run, stop and record it under
Blocked — that is the two-symptom rule, and citing makes it visible rather than
invisible.
