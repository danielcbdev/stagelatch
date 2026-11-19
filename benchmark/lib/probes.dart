/// The registry of probes, by command-line name.
library;

import 'package:stagelatch_bench/probe.dart';
import 'package:stagelatch_bench/probe_embedded.dart';

/// Every probe name accepted on the command line.
const probeNames = ['embedded'];

/// The probe called [name], caching in [cacheDir] when given.
Probe probeNamed(String name, {String? cacheDir}) => switch (name) {
  'embedded' => EmbeddedProbe(cacheDir: cacheDir),
  _ => throw ArgumentError.value(name, 'probe', 'one of $probeNames'),
};
