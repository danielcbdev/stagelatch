/// The argument names of an ICU message (docs/specs/rules.md, `l10n`).
library;

// What the scan is reading. `text` is a message or a branch body; the
// other four are the parts of one `{...}` argument.
const _text = 0;
const _name = 1;
const _type = 2;
const _options = 3;
const _style = 4;

const _apostrophe = 0x27;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _comma = 0x2C;

/// The names of the arguments of [message], an ICU message as found in an
/// ARB file: `{name}`, `{count, plural, ...}`, `{gender, select, ...}`,
/// typed arguments such as `{when, date, yMd}`, and the arguments inside
/// the branches of a plural or a select.
///
/// Quoted text is literal: `'{'` is not an argument, and `''` is an
/// apostrophe. A single apostrophe that does not precede a brace is
/// ordinary text. Keywords of a plural or select (`one`, `=0`, `other`,
/// `offset:1`) are not arguments.
///
/// Never throws, and tolerates unbalanced braces by returning what it
/// found. It is one left-to-right pass with an explicit stack, so the
/// nesting depth of a message cannot overflow the call stack and the cost
/// is linear in its length (security S6).
Set<String> icuArguments(String message) {
  final found = <String>{};
  final length = message.length;
  // One entry per open construct: what it is reading, and where the part
  // it is reading started.
  final kinds = <int>[_text];
  final marks = <int>[0];
  var i = 0;

  void push(int kind, int mark) {
    kinds.add(kind);
    marks.add(mark);
  }

  void pop() {
    kinds.removeLast();
    marks.removeLast();
  }

  void add(int from, int to) {
    final name = message.substring(from, to).trim();
    if (name.isNotEmpty) found.add(name);
  }

  while (i < length) {
    final c = message.codeUnitAt(i);
    switch (kinds.last) {
      case _text:
        if (c == _apostrophe) {
          i = _afterApostrophe(message, i);
          continue;
        }
        if (c == _openBrace) {
          push(_name, i + 1);
        } else if (c == _closeBrace && kinds.length > 1) {
          pop();
        }
        i++;
      case _name:
        if (c == _comma) {
          add(marks.last, i);
          kinds[kinds.length - 1] = _type;
          marks[marks.length - 1] = i + 1;
          i++;
        } else if (c == _closeBrace) {
          add(marks.last, i);
          pop();
          i++;
        } else if (c == _openBrace) {
          // A brace inside a name is malformed: drop the argument and let
          // this brace start a new one.
          pop();
        } else {
          i++;
        }
      case _type:
        if (c == _comma) {
          final type = message.substring(marks.last, i).trim();
          final branches =
              type == 'plural' || type == 'select' || type == 'selectordinal';
          kinds[kinds.length - 1] = branches ? _options : _style;
          i++;
        } else if (c == _closeBrace) {
          pop();
          i++;
        } else {
          i++;
        }
      case _style:
        if (c == _closeBrace) pop();
        i++;
      case _options:
        if (c == _openBrace) {
          push(_text, i + 1);
        } else if (c == _closeBrace) {
          pop();
        }
        i++;
    }
  }
  if (kinds.last == _name) add(marks.last, length);
  return found;
}

/// The offset after the apostrophe at [at], following the ICU quoting
/// rules: `''` is one apostrophe, an apostrophe before a brace quotes
/// everything up to the next single apostrophe, and any other apostrophe
/// is text.
int _afterApostrophe(String message, int at) {
  final length = message.length;
  if (at + 1 >= length) return length;
  final next = message.codeUnitAt(at + 1);
  if (next == _apostrophe) return at + 2;
  if (next != _openBrace && next != _closeBrace) return at + 1;
  var i = at + 1;
  while (i < length) {
    if (message.codeUnitAt(i) == _apostrophe) {
      if (i + 1 < length && message.codeUnitAt(i + 1) == _apostrophe) {
        i += 2;
        continue;
      }
      return i + 1;
    }
    i++;
  }
  return length;
}
