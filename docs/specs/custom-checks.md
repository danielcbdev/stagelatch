# Custom checks specification (1.0.0)

Status: **Draft. Not approved for implementation.** This is two releases away. It records the intended direction so that earlier work does not block it. It must be revisited and re-approved before plan 05 starts.

## 1. Goal

Let a team add its own rules, reported, filtered, suppressed and baselined exactly like built-in ones, without stagelatch entering the project's dependency graph (ADR-0004).

## 2. Constraint that drives the design

The tool runs from a global activation. It cannot `import` code from the project it checks, and the project cannot depend on the tool without bringing back the version conflicts ADR-0004 avoids. So a custom check must run in **its own process**.

## 3. Proposed shape

- A custom check is an executable started by stagelatch that speaks a line-delimited JSON protocol on stdin and stdout.
- The protocol is the public contract. A small, dependency-free Dart package (`stagelatch_core`, to be evaluated at 1.0.0 as `CLAUDE.md` says) implements it so that authors write a class, not a protocol loop.
- Declaration in config:

```yaml
custom_checks:
  team:
    run: [dart, run, tool/stagelatch_checks.dart]
    rules:
      no-print: error
```

- Rule IDs are `<check>/<rule>` like any other: `team/no-print`. A custom check ID may not shadow a built-in one.

## 4. Protocol sketch

Every message is one JSON object on one line.

| Direction | Message | Purpose |
|---|---|---|
| tool to check | `{"type":"init","protocol":1,"entry":"pre-commit","settings":{...}}` | Handshake |
| check to tool | `{"type":"ready","protocol":1,"rules":[{"id":"team/no-print","summary":"..."}]}` | Declares rules |
| tool to check | `{"type":"run","changes":[{"path":"lib/a.dart","kind":"modified"}]}` | Starts the run |
| check to tool | `{"type":"read","id":1,"path":"lib/a.dart","side":"snapshot"}` | Asks for snapshot content |
| tool to check | `{"type":"content","id":1,"text":"..."}` | Answers; `text` is null when unreadable |
| check to tool | `{"type":"finding","rule":"team/no-print","path":"lib/a.dart","line":3,"column":3,"message":"..."}` | Reports |
| check to tool | `{"type":"done"}` | Ends |

- The check reads files **only** through `read`, so it sees the snapshot, never the working tree.
- Custom checks are verify-phase only; they cannot produce fixes in 1.0.0.
- Protocol violations, a crash, or a timeout are an internal error naming the check (exit 70).

## 5. Security position

This is the one place a config key names a command, an explicit exception to rule S1.

- It is acceptable for the same reason a project's test suite is: the repository already contains code its contributors run.
- On pull requests from forks, CI would run fork-supplied code. The documentation must say so, and `ci` gets a `--no-custom-checks` flag.
- The command runs with an argument list, never through a shell; the working directory is the repository root.

## 6. Determinism

The tool cannot enforce determinism of third-party code. The documentation states the requirement; `doctor` lists configured custom checks so they are visible.

## 7. What earlier versions must preserve

- `Check`, `CheckContext` and `Finding` stay free of anything that cannot cross a process boundary as JSON.
- Rule validation in the config loader must be able to accept rule IDs declared at run time.
- The `custom_checks` key is reserved: until 1.0.0 the loader rejects it with `custom_checks requires stagelatch >= 1.0.0.`

## 8. Open questions for the 1.0.0 design review

1. Is a separate `stagelatch_core` package worth its release overhead, or is documenting the protocol enough?
2. Should custom checks receive `DartFileFacts` on request, or only raw text?
3. One process per run, or kept alive across pre-push refs?
4. Timeout policy and its default.
