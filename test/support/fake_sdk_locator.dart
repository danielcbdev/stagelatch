import 'package:stagelatch/src/application/config/config.dart';
import 'package:stagelatch/src/application/ports/sdk_locator.dart';

/// An [SdkLocator] that returns [sdk], or throws [error] when given.
final class FakeSdkLocator implements SdkLocator {
  /// Creates a locator.
  new({
    this.sdk = const ResolvedSdk(
      root: '/sdk',
      dartExecutable: '/sdk/bin/dart',
      flutterExecutable: null,
      version: '3.13.0',
      source: SdkSource.path,
    ),
    this.error,
  });

  /// What [locate] returns.
  final ResolvedSdk sdk;

  /// What [locate] throws instead, when not null.
  final Exception? error;

  /// How many times [locate] was called.
  int calls = 0;

  @override
  Future<ResolvedSdk> locate(Config config) async {
    calls++;
    if (error case final error?) throw error;
    return sdk;
  }
}
