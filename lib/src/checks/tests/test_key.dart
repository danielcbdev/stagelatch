/// How a test is identified across two versions of a file, and which files
/// hold tests.
library;

import 'package:stagelatch/src/domain/dart/dart_file_facts.dart';
import 'package:stagelatch/src/domain/package_map.dart';
import 'package:stagelatch/src/domain/repo_path.dart';

/// The key of [call]: its enclosing groups, outermost first, then its own
/// description. Two calls with the same key are "the same test" for
/// `tests/new-skip`.
///
/// Each part is length-prefixed, so no description, however it is written,
/// can make two different lists of parts produce one key.
String testKey(TestCall call) => [
  for (final part in [...call.groups, call.description]) '${part.length}:$part',
].join('|');

/// Whether [path] is a test file: a `.dart` file under the `test/`
/// directory of the package that owns it, whose name ends with
/// `_test.dart`. A path no package owns is not one.
bool isTestFile(RepoPath path, PackageMap packages) {
  if (path.extension != '.dart' || !path.basename.endsWith('_test.dart')) {
    return false;
  }
  final package = packages.packageOf(path);
  if (package == null) return false;
  final root = package.root;
  final relative = root == null
      ? path.value
      : path.value.startsWith('${root.value}/')
      ? path.value.substring(root.value.length + 1)
      : null;
  return relative != null && relative.startsWith('test/');
}
