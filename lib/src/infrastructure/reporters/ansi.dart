/// SGR sequences for the console reporter.
///
/// Color is applied only when the reporter was asked for it. The wrapped
/// text is unchanged, so stripping the sequences yields the plain report
/// (docs/specs/cli.md section 4).
library;

/// Red: a finding of severity error.
const int ansiError = 31;

/// Yellow: a finding of severity warning.
const int ansiWarning = 33;

/// Dim: a rule id.
const int ansiDim = 2;

/// Reset, returned to after every colored span.
const int ansiReset = 0;

/// Wraps [text] in the SGR sequence for [code], then resets.
String ansi(String text, int code) =>
    '\u001b[${code}m$text\u001b[${ansiReset}m';
