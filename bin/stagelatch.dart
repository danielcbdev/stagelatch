import 'dart:io';

import 'package:stagelatch/stagelatch.dart';

/// Entry point of the `stagelatch` executable.
///
/// Prints the version only; the command runner replaces this body in plan
/// 01, task 13.
void main() {
  stdout.writeln('stagelatch $packageVersion');
}
