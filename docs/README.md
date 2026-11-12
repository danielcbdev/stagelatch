# stagelatch documentation

Status: **Approved by the owner on 2026-11-12.** Nothing here is implemented yet.

## Reading order for an implementing agent

1. [`CLAUDE.md`](../CLAUDE.md): scope, fixed decisions, roadmap.
2. [`architecture.md`](architecture.md): layers, ports, domain model, pipeline.
3. [`engineering/`](engineering/): how code is written, tested, secured and merged.
   - [`coding-standards.md`](engineering/coding-standards.md)
   - [`security.md`](engineering/security.md)
   - [`testing.md`](engineering/testing.md)
   - [`workflow.md`](engineering/workflow.md)
4. [`specs/`](specs/README.md): what the software must do, with exact values.
5. [`plans/`](plans/README.md): how to build it, task by task.
6. [`adr/`](adr/README.md): why each decision was made.

## Precedence

`CLAUDE.md` > ADRs > specs > plans.

- A plan never overrides a spec. If they disagree, stop, fix the plan, and say so in the pull request.
- A spec may *refine* `CLAUDE.md` (make it more precise). Every refinement is listed in [`specs/README.md`](specs/README.md#refinements-to-claudemd) and needs the owner's approval before `CLAUDE.md` is updated to match.
- A spec never *contradicts* `CLAUDE.md`. If implementation shows a fixed decision is wrong, stop and ask the owner; do not work around it.

## Language

Everything under `docs/`, all code, comments, commit messages and CLI output are in English. Conversation with the owner is in Portuguese.
