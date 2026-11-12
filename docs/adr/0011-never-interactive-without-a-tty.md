# ADR-0011: Never interactive without a TTY

- Status: Accepted
- Date: 2026-11-11

## Context

The tool runs inside git hooks, CI jobs and AI agents. In all three, a prompt waits forever.

## Decision

- No command reads from stdin to ask a question when stdin or stdout is not a terminal. `init` proceeds with detected defaults.
- In version 0.x no command prompts at all, TTY or not. Choices are made with flags.
- Color and cursor control are emitted only when stdout is a terminal and `NO_COLOR` is unset.
- `run pre-push` reads stdin because git supplies ref lines there. That is data, not a prompt.
- `--reporter json` writes a machine-readable report so that scripts and agents never parse terminal text.

## Consequences

- TTY detection and `NO_COLOR` are read once in the composition root and passed down as values.
- An acceptance scenario runs every command with stdin closed and asserts that it terminates and prints no escape sequences.
