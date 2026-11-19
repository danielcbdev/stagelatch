/// The registry of probes, by command-line name.
library;

import 'package:path/path.dart' as p;
import 'package:stagelatch_bench/probe.dart';
import 'package:stagelatch_bench/probe_delegated.dart';
import 'package:stagelatch_bench/probe_embedded.dart';

/// Every probe name accepted on the command line.
const probeNames = [
  'embedded',
  'delegated',
  'delegated-idle',
  'delegated-files',
];

/// The probe called [name], caching in [cacheDir] when given.
///
/// The server always needs a cache directory; without [cacheDir] it gets a
/// fresh one under [scratchDir], so the run is cold.
Probe probeNamed(String name, {required String scratchDir, String? cacheDir}) {
  String serverCache() =>
      cacheDir ??
      p.join(scratchDir, 'cold-${DateTime.now().microsecondsSinceEpoch}');
  return switch (name) {
    'embedded' => EmbeddedProbe(cacheDir: cacheDir),
    'delegated' => DelegatedProbe(cacheDir: serverCache()),
    'delegated-files' => DelegatedProbe(
      cacheDir: serverCache(),
      roots: RootsMode.files,
    ),
    'delegated-idle' => DelegatedProbe(
      cacheDir: serverCache(),
      wait: WaitStrategy.idle,
    ),
    _ => throw ArgumentError.value(name, 'probe', 'one of $probeNames'),
  };
}
