/// A `stagelatch` executable on `PATH` for the end-to-end hook tests.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// A directory containing `stagelatch` (and `stagelatch.bat` on Windows)
/// that runs this package's executable.
///
/// The caller deletes the directory. The scripts use LF, except the
/// Windows batch file, which `cmd` requires to use CRLF.
Future<String> createShimDirectory() async {
  final directory = await Directory.systemTemp.createTemp('stagelatch_shim_');
  final program = p.join(Directory.current.path, 'bin', 'stagelatch.dart');
  final quoted = program.replaceAll("'", r"'\''");
  final script =
      '#!/bin/sh\n'
      'unset DART_VM_OPTIONS\n'
      'unset DART_VM_SERVICE\n'
      "exec dart '$quoted' ${r'"$@"'}\n";
  await File(p.join(directory.path, 'stagelatch')).writeAsString(script);
  if (Platform.isWindows) {
    final bat = '@echo off\r\ndart "$program" %*\r\n';
    await File(p.join(directory.path, 'stagelatch.bat')).writeAsString(bat);
  } else {
    await Process.run('chmod', ['755', p.join(directory.path, 'stagelatch')]);
  }
  return directory.path;
}

/// [shim] in front of the current `PATH`, so the hook finds it first.
String pathWithShim(String shim) {
  final separator = Platform.isWindows ? ';' : ':';
  final current = Platform.environment['PATH'] ?? '';
  return '$shim$separator$current';
}
