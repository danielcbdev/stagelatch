# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub:
**Security > Report a vulnerability** on
<https://github.com/danielcbdev/stagelatch>.

Do not open a public issue for a security problem.

Include what you ran, what you expected and what happened. A minimal
repository that reproduces the problem helps most.

## What counts

stagelatch runs with your privileges on every commit, writes to the git index
and installs hook scripts. Reports about any of these are in scope:

- loss or corruption of uncommitted work;
- a write outside the repository or its git directory;
- execution of a program other than `git` or the resolved Dart SDK;
- terminal or workflow-command injection through repository content;
- a verdict that can be forced to "pass" by repository content alone.

The rules the code is held to are in
[`docs/engineering/security.md`](docs/engineering/security.md).

## Supported versions

Only the latest released version receives fixes.
