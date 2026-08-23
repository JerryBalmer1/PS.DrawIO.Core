# `.agent/` — agent execution protocol

| File | Committed? | Who writes | Who reads | When |
|------|------------|------------|-----------|------|
| [TRAPS.md](TRAPS.md) | Yes | Agents (append only) when a failure costs time | Every agent, once | Before any command on a task |
| [EXECUTION.template.md](EXECUTION.template.md) | Yes | Humans / protocol maintainers | Agents | When starting a run (copy structure) |
| `EXECUTION.md` | **No** (gitignored) | The agent running the task | The same agent; the next agent on handoff | Cleared and rewritten each run |

**TRAPS.md is the valuable artifact.** It should grow. It records tool and
process facts paid for with real time. Do not edit it to make a task pass.

`EXECUTION.md` is a per-run scratch log. It is not history; git history is.
Keep it current so a lost context window does not lose the plan.
