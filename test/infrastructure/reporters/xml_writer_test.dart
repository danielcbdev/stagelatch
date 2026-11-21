import 'package:stagelatch/src/infrastructure/reporters/xml_writer.dart';
import 'package:test/test.dart';

void main() {
  test('escaping covers the five entities and drops characters XML 1.0 '
      'forbids', () {
    expect(
      escapeXml('<a & "b">', attribute: true),
      '&lt;a &amp; &quot;b&quot;&gt;',
    );
    expect(escapeXml("a'", attribute: true), 'a&apos;');
    expect(escapeXml('a\u0000b\u000bc', attribute: false), 'abc');
  });

  test('text escaping leaves quotes alone and attribute escaping does not', () {
    expect(escapeXml('<a & "b\'>', attribute: false), '&lt;a &amp; "b\'&gt;');
    expect(
      escapeXml('<a & "b\'>', attribute: true),
      '&lt;a &amp; &quot;b&apos;&gt;',
    );
  });

  test('writer emits a nested element with escaped text and attributes', () {
    final out = StringBuffer();
    XmlWriter(out)
      ..startElement('root', {'id': 'a&b'})
      ..startElement('child')
      ..text('x<y')
      ..endElement()
      ..emptyElement('empty', {'v': '"'})
      ..endElement();
    expect(
      out.toString(),
      '<root id="a&amp;b"><child>x&lt;y</child><empty v="&quot;"/></root>',
    );
  });
}
