/// Change-aware quality gate for Flutter and Dart repositories.
///
/// stagelatch is a command-line tool. In 1.0.0 this library exports only
/// `packageVersion`; nothing under `lib/src` is public API. Custom checks
/// speak the out-of-process protocol; they do not import this package.
library;

export 'src/version.dart' show packageVersion;
