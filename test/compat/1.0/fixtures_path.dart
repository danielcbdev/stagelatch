/// Shared paths for the 1.0 compatibility fixtures.
library;

import 'dart:io';

/// Directory that holds the frozen 1.0 fixtures.
final Directory compat10Fixtures = Directory('test/compat/1.0/fixtures');

/// Reads a fixture file relative to [compat10Fixtures].
String readCompatFixture(String relativePath) =>
    File('${compat10Fixtures.path}/$relativePath').readAsStringSync();
