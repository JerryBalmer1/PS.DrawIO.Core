# EXECUTION_RECORDS

Completed agent execution logs for this repository.

## Purpose

These files are the project's working history of how tasks were actually done.
They exist so later analysis can reconstruct decisions, failures, and verification
without relying on overwritten live logs.

## Naming

One file per completed task:

```text
yyyy-MM-dd-HH-mm-ss-EXECUTION.md
```

Example: `2026-08-23-14-05-09-EXECUTION.md`

- `yyyy-MM-dd` — calendar date
- `HH` — 24-hour clock (00–23), not 12-hour
- `mm` — minutes
- `ss` — seconds
- suffix — always `-EXECUTION.md`

Do not swap `HH` and `MM`. `MM` is months; using it for minutes sorts wrongly
and is silently useless.

## How a record is created

At task end, after every plan box is ticked or explicitly marked blocked:

```powershell
$stamp = Get-Date -Format 'yyyy-MM-dd-HH-mm-ss'
Move-Item .agent/EXECUTION.md ".agent/EXECUTION_RECORDS/$stamp-EXECUTION.md"
```

Archive only a finished log. A log archived mid-task is a record of nothing.

The live file `.agent/EXECUTION.md` remains gitignored. This directory is tracked.

## Append-only set (documented prohibition)

As a set, these records are **append-only**:

- An existing record is **never** edited, renamed, or deleted by an agent.
- New records may be added.
- Reading prior records is encouraged — often the fastest way to see how
  something was done.

This is a **documented prohibition**, not a filesystem permission. The agent
runs with the operator's rights and can technically overwrite files. Enforcement
is visibility: the build warns when records are untracked or when a tracked
record is modified. Tampering is made visible, not impossible.
