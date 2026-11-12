import 'package:stagelatch/src/application/errors.dart';
import 'package:stagelatch/src/cli/exit_codes.dart';
import 'package:test/test.dart';

void main() {
  test('exit codes have the documented values', () {
    expect(ExitCode.pass.code, 0);
    expect(ExitCode.findings.code, 1);
    expect(ExitCode.usage.code, 64);
    expect(ExitCode.internal.code, 70);
    expect(ExitCode.config.code, 78);
  });

  test('each failure maps to its own exit code', () {
    expect(ExitCode.forException(const UsageException('x')), ExitCode.usage);
    expect(ExitCode.forException(const ConfigException('x')), ExitCode.config);
    expect(
      ExitCode.forException(const InternalException('x')),
      ExitCode.internal,
    );
  });
}
