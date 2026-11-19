import 'package:stagelatch/src/checks/format/first_difference.dart';
import 'package:stagelatch/src/domain/location.dart';
import 'package:test/test.dart';

void main() {
  test('firstDifference returns the 1-based line and column', () {
    expect(firstDifference('a\nbc\n', 'a\nbd\n'), const Position(2, 2));
    expect(firstDifference('a', 'a\n'), const Position(1, 2));
  });

  test('a difference at the very start is 1:1', () {
    expect(firstDifference('x', 'y'), const Position(1, 1));
  });

  test('CRLF counts as one line break', () {
    expect(firstDifference('a\r\nb\r\nc', 'a\r\nb\r\nd'), const Position(3, 1));
  });

  test('a longer first text differs where the second one ends', () {
    expect(firstDifference('ab\nc', 'ab\n'), const Position(2, 1));
  });
}
