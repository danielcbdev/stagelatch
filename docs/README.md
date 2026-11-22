# stagelatch documentation

Status: **Approved by the owner on 2026-11-12.** Fully implemented: plans 00 to 05 are done and the current release is `1.0.x`. The plans stay in the repository as the record of how each release was built.

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

## For users

- [`../README.md`](../README.md): what it does, quick start, adoption guide, benchmark.
- [`rules.md`](rules.md): the rule reference. It is generated from the registered checks by `dart run tool/generate_rules_doc.dart`; a test fails when it is stale.
- [`custom-checks.md`](custom-checks.md): how to write an out-of-process custom check (1.0.0); reference under [`../example/custom_check/`](../example/custom_check/).
- [`../schema/stagelatch.schema.json`](../schema/stagelatch.schema.json): the JSON Schema of `stagelatch.yaml`.

## Precedence

`CLAUDE.md` > ADRs > specs > plans.

- A plan never overrides a spec. If they disagree, stop, fix the plan, and say so in the pull request.
- A spec may *refine* `CLAUDE.md` (make it more precise). Every refinement is listed in [`specs/README.md`](specs/README.md#refinements-to-claudemd) and needs the owner's approval before `CLAUDE.md` is updated to match.
- A spec never *contradicts* `CLAUDE.md`. If implementation shows a fixed decision is wrong, stop and ask the owner; do not work around it.

## Language

Everything under `docs/`, all code, comments, commit messages and CLI output are in English. Conversation with the owner is in Portuguese.

## How this repository was built

stagelatch was developed with AI coding agents working under a written contract, and the repository keeps that contract in the open:

- [`CLAUDE.md`](../CLAUDE.md) is the agent's brief: scope, fixed decisions and roadmap. It is the top of the precedence chain above.
- [`plans/`](plans/README.md) are the task-by-task implementation plans the agents executed. Each task names its branch, its files, its interfaces and its verification steps, and each one landed as its own reviewed pull request. The "for agentic workers" header on a plan is an instruction to the agent that executed it, not something a contributor has to follow.
- The owner decides every fixed decision, approves every spec and merges every pull request. Where an agent found a decision to be wrong, the work stopped and the question went to the owner; the ADRs record the outcome.

None of this touches the product's guarantees: the tool itself is deterministic, offline and has no AI in its blocking path ([ADR-0003](adr/0003-deterministic-verdicts.md)). Human contributors can ignore the agent-specific parts and start from [`CONTRIBUTING.md`](../CONTRIBUTING.md).
