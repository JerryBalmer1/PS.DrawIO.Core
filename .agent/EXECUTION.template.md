# Execution log

Copy this structure into `.agent/EXECUTION.md` at the start of a run.
`EXECUTION.md` is gitignored and cleared each run. Write it **as the work
happens**, not at the end — a context blowout must not lose the log.

Status markers: `[x]` done, `[ ]` not started, `[!]` blocked, `[~]` partial.

Rules:

- Record reasoning only when an attempt **fails**. Successful steps get one line.
- No decorative formatting.
- Two attempts maximum per task item. On the second failure, move the item to
  **Blocked** and continue.
- End every task with the **Verification** block (raw command output).

---

# Execution log
Run: <timestamp> | Repo: <name>
Task: <one line>

## Plan
- [ ] T1 <task>
- [ ] T2 <task>

## T<n> — <task name>
Attempt 1: <what was tried>
  Result: OK | FAIL — <what happened>
  Cause: <TRAPS.md id if applicable, else the actual cause>
Attempt 2: <only if attempt 1 failed>
  Result: ...

## Results
- [x] T1 — <outcome>
- [!] T2 — BLOCKED, see below

## Blocked
<anything abandoned after two attempts, with the error>

## Verification
<raw output of the four verification commands>

## For the next agent
<working tree state, what is done, what is not, what to do next>
