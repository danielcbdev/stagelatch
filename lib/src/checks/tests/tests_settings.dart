/// The parameters of the `tests` check (docs/specs/config.md, section 3).
library;

/// Parameters of the `tests` check.
final class TestsSettings {
  /// Creates the settings.
  const new({this.functions = const ['test', 'testWidgets', 'group']});

  /// The functions whose calls count as tests or groups.
  final List<String> functions;
}
