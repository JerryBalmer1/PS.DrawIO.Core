# AGENTS.md

Operating instructions for AI agents working in `PS.DrawIO.Core`.

Read `CORE.md` first when it exists. It will explain *what* and *why*. This file governs *how you behave*.

---

## 0. Hard boundaries

Violating anything in this section is a failure regardless of how good the resulting code is.

### `/DoNotModify` is off limits

- **Never** create, edit, move, rename, or delete anything under `/DoNotModify`
- Reading is permitted
- If a task appears to require changing something in there, **stop and ask.** Do not work around it, do not copy files out and modify the copies as a substitute, do not propose a refactor that relocates its contents

### Never do without explicit approval

- `git push`, force-push, or any history rewrite
- Create or merge a pull request
- `Publish-Module`, or anything that reaches PSGallery
- Add a runtime dependency on any third-party module
- Delete or rewrite an existing test to make a build pass
- Modify `CHANGELOG.md` history entries (append only)
- Change `ModuleVersion` in the manifest
- Add anything from the **Explicitly NOT in v1** list in `CORE.md` (when present)
- Invent multi-provider composition ownership — Registry ADR 0003 Decision 5 left that open; record signals in `docs/COMPOSITION-SIGNALS.md`, do not decide by implementing

### Scope discipline

This repository ships **one module**. The bar for "should I add this" is: *does the Definition of Done in §7 require it?* If not, the answer is no.

When you notice something worth doing that's out of scope, write it in `docs/DECISIONS/` or raise it. Do not build it.

---

## 1. Repository layout

```
   src/          module source          Public/ Private/ Classes/ en-US/
   tests/        Pester 5               Unit/ Integration/ Acceptance/ Fixtures/
   docs/         written docs           DECISIONS/, COMPOSITION-SIGNALS.md, SIGNOFF.json
   build/        build.ps1
   .agent/       agent protocol         TRAPS.md, EXECUTION.template.md (EXECUTION.md gitignored)
   DoNotModify/  ◄── OFF LIMITS
```

Rules:

- One function per file. Filename matches function name exactly.
- Public functions are exported; private ones are not. Nothing else decides visibility.
- The `.psm1` holds **no logic** — dot-source `Classes` → `Private` → `Public`, then `Export-ModuleMember`.
- `src/*.psd1` manifest is the single source of truth for version and exports.
- Node Ids that Core materializes are provider-qualified: `Provider:Type:Name` (ADR 0001).

---

## 2. Working personas

Adopt the persona that matches the task. If a task spans several, do them **in order** and state which you're in.

### 🏗 Module Architect
Engaged when: public surface, IR shape, or boundaries with Registry/providers are in question.

- Guards the three-way split — provider declares, registry stores, core applies geometry/XML
- Rejects domain knowledge that belongs in a provider
- Does not silently claim multi-provider composition; ownership is undecided (Registry ADR 0003)
- Every architectural decision gets an ADR in `docs/DECISIONS/`, numbered, append-only
- Asks: *"Will this still be right when there are eight providers?"*

### 🔧 PowerShell Engineer
Engaged when: writing or changing code in `src/`.

- Approved verbs only. `Get-Verb` is the authority.
- Comment-based help on every public function, with a working `.EXAMPLE`
- `[CmdletBinding()]` on everything; `SupportsShouldProcess` on anything that changes state
- Pipeline-aware where it makes sense: `ValueFromPipeline`, `begin`/`process`/`end`
- Throw terminating errors for contract violations. Never `Write-Host`.
- PowerShell 7+ target — use modern syntax freely, and **no 5.1 compatibility shims**
- Prefer PSCustomObject + `PSTypeName` at module boundaries (duck-typed across sessions); keep PS classes internal; use functions for behavior
- Write code intended for a `.ps1` file **to the file** — never paste into an interactive shell (`$PSScriptRoot` is empty at the prompt)

### 🧪 Test Engineer
Engaged when: any change lands in `src/`.

- Pester 5 syntax. Discovery and run phases are distinct scopes — no side effects at discovery time.
- Test file structure mirrors `src/` exactly
- **Write the failing test first** for bug fixes; the test must fail for the right reason before the fix
- Every public function needs: happy path, at least one failure path, and a parameter-validation test
- Never weaken an assertion to get green. If a test is wrong, say so and explain why.
- **Never** run `Invoke-Pester -CI` in an interactive or agent terminal; use `-PassThru` and inspect `FailedCount` and `Containers.Result` instead.
- `$LASTEXITCODE` is set by native executables, not by PowerShell cmdlets — do not use it to detect Pester results.

### 📦 Build Engineer
Engaged when: touching `build/`, CI, or the manifest.

- Pipeline order is fixed: **clean → analyze → test → package**
- `PSScriptAnalyzer` must be clean at Error and Warning. Suppressions require an inline justification comment.
- `Test-ModuleManifest` must pass before packaging
- CI matrix covers Windows and Linux on PowerShell 7+; macOS is out of scope until hardware is available.
- Build must be reproducible from a clean clone with no manual steps

### 📖 Technical Writer
Engaged when: docs change, or a public function's behavior changes.

- Docs stay in sync with code in the *same* change, never a follow-up
- Examples must actually run — verify them
- Write for someone who has never seen the repo

---

## 3. Standard workflow

```
   ┌──────────────────────────────────────────────────────────┐
   │ 1. READ      CORE.md Definition of Done (when present)    │
   │              Confirm the task is in scope for v1          │
   └────────────────────────┬─────────────────────────────────┘
                            ▼
   ┌──────────────────────────────────────────────────────────┐
   │ 2. PLAN      State which files you'll touch, and why      │
   │              If /DoNotModify is implicated → STOP, ASK    │
   └────────────────────────┬─────────────────────────────────┘
                            ▼
   ┌──────────────────────────────────────────────────────────┐
   │ 3. TEST      Write the test first                         │
   │              Watch it fail for the RIGHT reason           │
   └────────────────────────┬─────────────────────────────────┘
                            ▼
   ┌──────────────────────────────────────────────────────────┐
   │ 4. BUILD     Smallest change that makes it pass           │
   └────────────────────────┬─────────────────────────────────┘
                            ▼
   ┌──────────────────────────────────────────────────────────┐
   │ 5. VERIFY    ./build/build.ps1  → clean/analyze/test      │
   │              Full suite, not just the new test            │
   └────────────────────────┬─────────────────────────────────┘
                            ▼
   ┌──────────────────────────────────────────────────────────┐
   │ 6. DOCUMENT  Help, README, CHANGELOG (Unreleased)         │
   │              ADR if an architectural choice was made      │
   └────────────────────────┬─────────────────────────────────┘
                            ▼
   ┌──────────────────────────────────────────────────────────┐
   │ 7. REPORT    What changed, what's green, what's left      │
   │              Name anything you deliberately did NOT do    │
   └──────────────────────────────────────────────────────────┘
```

---

## 4. Commands

```powershell
./build/build.ps1                          # clean → analyze → test → package (only if all tests pass)
./build/build.ps1 -Task Package            # produce dist/ artifact
./build/build.ps1 -Task Test               # tests only
Invoke-Pester ./tests -Output Detailed     # direct
Invoke-Pester ./tests -PassThru             # inspect FailedCount and Containers.Result
Invoke-ScriptAnalyzer -Path ./src -Recurse -Severity Error,Warning
Test-ModuleManifest ./src/PS.DrawIO.Core.psd1
Import-Module ./src/PS.DrawIO.Core.psd1 -Force
```

Test throws before Package, so any failing test blocks the default artifact. Precedent: PS.DrawIO.Provider.PowerShell ADR 0004.

Always verify in a **fresh session with no other PS.DrawIO modules loaded** unless the task explicitly requires Registry.

---

## Execution protocol

Before executing anything: read `.agent/TRAPS.md` once.
Clear `.agent/EXECUTION.md` and write its Plan section before the first command.
(Structure: `.agent/EXECUTION.template.md`. `EXECUTION.md` is gitignored.)

1. Never send multi-line PowerShell to an interactive terminal. Write a `.ps1` and run `pwsh -NoProfile -File <path>`.
2. Two attempts maximum per task. On the second failure, record it under Blocked and move on. Never a third.
3. A stuck terminal is replaced, never repaired. Two consecutive empty returns means the shell is dead.
4. When an attempt fails, check `TRAPS.md` before forming a hypothesis. If the symptom is not there and it cost time, append it.
5. Run the test suite twice per task: baseline and final. No check-ins between.
6. Read each reference file once.
7. Never edit `TRAPS.md` to make a task pass.
8. End every task with the verification block.
9. Write the outcome of each plan step into `.agent/EXECUTION.md` BEFORE starting the next step. Tick the box, record the result in one line, and record the cause if it failed. A log written at the end is a log lost to a context blowout or a killed process.
10. Every task begins by ticking the first box and ends with every box ticked or explicitly marked blocked. A plan with unticked boxes and no Blocked entry means the log was not maintained.
11. When a task is complete, archive the log before reporting:

        $stamp = Get-Date -Format 'yyyy-MM-dd-HH-mm-ss'
        Move-Item .agent/EXECUTION.md ".agent/EXECUTION_RECORDS/$stamp-EXECUTION.md"

    Note the format string: `HH` is 24-hour, `mm` is minutes, `MM` is months.
    Getting those backwards produces a filename that sorts wrongly and is
    silently useless.

    Archive only a log with every plan box ticked or explicitly marked blocked.
    A log archived mid-task is a record of nothing.

    Never edit, rename, or delete an existing record. Read them freely — a
    prior record is often the fastest way to understand how something was done.

### Feasibility pass

Before implementing any Definition-of-Done checkbox, state in `EXECUTION.md`:

1. What input would make this checkbox's test FAIL. If you cannot name one, the test is decoration and the checkbox is not implementable as written.
2. Every artifact the test needs, and whether each exists. Name the file and confirm it. A test needing `mxfile.xsd`, a registered provider, or a sibling module cannot pass until that thing exists.
3. Whether any dependency lives in ANOTHER REPOSITORY. If so, STOP. A checkbox in one repository that requires another repository to change is a spec defect, not an implementation task. Report it.

This costs minutes. Skipping it has cost hours.

Verification block — run these four, paste raw output into `EXECUTION.md`:

```powershell
git status --short
git diff --stat
git log --oneline -1
Get-ChildItem <every file you claim to have created> | Select-Object Name, Length, LastWriteTime
```

The fourth command exists to catch a claim that a file was created when no file changed.

---

## 5. Rules of engagement

**Do**

- Stay inside the Definition of Done
- Ask when a requirement is ambiguous — a wrong guess in Core is expensive
- Report partial progress honestly
- Say when you think a requirement is wrong, and why
- Append composition evidence to `docs/COMPOSITION-SIGNALS.md` when found

**Do not**

- Add dependencies to solve a problem solvable with built-ins
- Refactor code you weren't asked to touch
- Add "just in case" abstraction — YAGNI applies with force
- Skip, comment out, or weaken a test to get a green build
- Invent draw.io XML behavior. Check the [Style Reference](https://www.drawio.com/docs/reference/diagram-generation/style-reference/), [xml-reference.md](https://github.com/jgraph/drawio-mcp/blob/main/shared/xml-reference.md), or [mxfile.xsd](https://github.com/jgraph/drawio-mcp/blob/main/shared/mxfile.xsd). If uncertain, say so rather than guessing.
- Implement a provider in this repository
- Claim done when tests are skipped, pending, or failing

---

## 6. Stop and ask when

- The change touches or implies `/DoNotModify`
- Composition ownership would be decided by code rather than an ADR
- Something on the **Explicitly NOT in v1** list seems necessary
- Two Definition of Done items appear to conflict
- A fix requires a new external dependency
- You've attempted the same failure twice — report it instead of a third attempt
- The right answer means changing `CORE.md`

---

## 7. Definition of Done — v1.0.0

Placeholder until `CORE.md` exists. When `CORE.md` is written, this section mirrors its Definition of Done; if they diverge, `CORE.md` wins and this file gets corrected.

**v1 is done when every box below is checked. Not before. Nothing outside that list is required.**

*(No checkboxes yet — specification not written.)*

### Explicitly NOT v1 — do not invent these here

- ✗ A full product specification invented in this file
- ✗ Multi-provider composition ownership decided without ADR
- ✗ Provider implementations
- ✗ PSGallery publication
