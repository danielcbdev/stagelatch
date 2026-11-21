import 'package:example_custom_check/no_print.dart';
import 'package:test/test.dart';

void main() {
  test('findPrintCall returns null when there is no print', () {
    expect(findPrintCall('void hello() {}\n'), isNull);
  });

  test('findPrintCall reports the first print call', () {
    const source = 'void hello() {\n  print("hi");\n}\n';
    final hit = findPrintCall(source);
    expect(hit, isNotNull);
    expect(hit!.line, 2);
    expect(hit.column, 3);
  });
}
