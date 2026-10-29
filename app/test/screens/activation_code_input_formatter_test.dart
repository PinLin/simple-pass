import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';
import 'package:simple_pass/screens/activation_code_input_formatter.dart';

const _formatter = ActivationCodeInputFormatter();

/// `|` marks a collapsed cursor; `[` and `]` mark a selection.
TextEditingValue _v(String marked) {
  final caret = marked.indexOf('|');
  if (caret >= 0) {
    return TextEditingValue(
      text: marked.replaceAll('|', ''),
      selection: TextSelection.collapsed(offset: caret),
    );
  }
  final start = marked.indexOf('[');
  final end = marked.indexOf(']') - 1;
  return TextEditingValue(
    text: marked.replaceAll('[', '').replaceAll(']', ''),
    selection: TextSelection(baseOffset: start, extentOffset: end),
  );
}

String _marked(TextEditingValue value) {
  final s = value.selection;
  if (s.isCollapsed) return '${value.text.substring(0, s.baseOffset)}|${value.text.substring(s.baseOffset)}';
  return '${value.text.substring(0, s.start)}[${value.text.substring(s.start, s.end)}]${value.text.substring(s.end)}';
}

String _format(String oldMarked, String newMarked) =>
    _marked(_formatter.formatEditUpdate(_v(oldMarked), _v(newMarked)));

String _type(String marked, String typed) {
  final old = _v(marked);
  final at = old.selection.start;
  final text = old.text.replaceRange(at, old.selection.end, typed);
  return _marked(
    _formatter.formatEditUpdate(
      old,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: at + typed.length),
      ),
    ),
  );
}

String _backspace(String marked) {
  final old = _v(marked);
  final s = old.selection;
  final from = s.isCollapsed ? s.baseOffset - 1 : s.start;
  return _marked(
    _formatter.formatEditUpdate(
      old,
      TextEditingValue(
        text: old.text.replaceRange(from, s.end, ''),
        selection: TextSelection.collapsed(offset: from),
      ),
    ),
  );
}

String _forwardDelete(String marked) {
  final old = _v(marked);
  final at = old.selection.baseOffset;
  return _marked(
    _formatter.formatEditUpdate(
      old,
      TextEditingValue(
        text: old.text.replaceRange(at, at + 1, ''),
        selection: TextSelection.collapsed(offset: at),
      ),
    ),
  );
}

void main() {
  group('a. typing at the end', () {
    test('the fifth character does not add a trailing hyphen', () {
      expect(_type('ABCD|', 'E'), 'ABCDE|');
    });

    test('the sixth character brings the hyphen with it', () {
      expect(_type('ABCDE|', 'F'), 'ABCDE-F|');
      expect(_type('ABCDE-FGHIJ|', 'K'), 'ABCDE-FGHIJ-K|');
    });

    test('typing a whole code one key at a time ends grouped, cursor at the end', () {
      var value = '|';
      for (final char in 'apscgykkaunezgcprdsm'.split('')) {
        value = _type(value, char);
      }
      expect(value, 'APSCG-YKKAU-NEZGC-PRDSM|');
    });

    test('backspacing a whole code never sticks on a hyphen', () {
      var value = 'APSCG-YKKAU-NEZGC-PRDSM|';
      final seen = <String>[];
      while (value != '|') {
        final next = _backspace(value);
        expect(next, isNot(value), reason: 'stuck at $value');
        seen.add(next);
        value = next;
      }
      expect(seen.length, 20);
      expect(seen.first, 'APSCG-YKKAU-NEZGC-PRDS|');
      expect(seen[3], 'APSCG-YKKAU-NEZGC-P|');
      expect(seen[4], 'APSCG-YKKAU-NEZGC|');
    });
  });

  group('b. deleting a lone hyphen', () {
    test('backspace right after a hyphen removes the character before it and regroups', () {
      expect(_backspace('ABCDE-|FGHIJ'), 'ABCD|F-GHIJ');
      expect(_backspace('ABCDE-|F'), 'ABCD|F');
      expect(_backspace('ABCDE-FGHIJ-|KLMNO'), 'ABCDE-FGHI|K-LMNO');
    });

    test('forward delete right before a hyphen removes the character after it', () {
      expect(_forwardDelete('ABCDE|-FGHIJ'), 'ABCDE|-GHIJ');
      expect(_forwardDelete('ABCDE|-F'), 'ABCDE|');
    });

    test('deleting a selection of just the hyphen removes the character before it', () {
      expect(_format('ABCDE[-]FGH', 'ABCDE|FGH'), 'ABCD|F-GH');
    });
  });

  group('c. editing in the middle', () {
    test('inserting regroups what follows and keeps the cursor after the typed character', () {
      expect(_type('AB|CDE-FGHIJ', 'X'), 'ABX|CD-EFGHI-J');
      expect(_type('ABCDE|-FGHIJ', 'X'), 'ABCDE-X|FGHI-J');
      expect(_type('ABCDE-|FGHIJ', 'X'), 'ABCDE-X|FGHI-J');
    });

    test('deleting regroups what follows and keeps the cursor where the character was', () {
      expect(_backspace('AB|CDE-FGHIJ'), 'A|CDEF-GHIJ');
      expect(_backspace('ABCDE-FG|HIJ'), 'ABCDE-F|HIJ');
      expect(_forwardDelete('AB|CDE-FGHIJ'), 'AB|DEF-GHIJ');
    });

    test('a symbol or space is ignored and the cursor does not move', () {
      expect(_type('ABCDE|', '-'), 'ABCDE|');
      expect(_type('ABCDE|', ' '), 'ABCDE|');
      expect(_type('ABCDE|', '_'), 'ABCDE|');
      expect(_type('ABCDE|', '\u200B'), 'ABCDE|');
    });

    test('digits outside base32 stay as typed for validation to reject', () {
      expect(_type('AB|', '0'), 'AB0|');
      expect(_type('AB|', '1'), 'AB1|');
      expect(_type('AB|CDE', '8'), 'AB8|CD-E');
      expect(_type('AB|', '９'), 'AB9|');
    });
  });

  group('d. pasting', () {
    test('with hyphens, spaces, lowercase or full-width forms, ends grouped with the cursor at the end', () {
      for (final pasted in [
        'APSCG-YKKAU-NEZGC-PRDSM',
        'apscg ykkau nezgc prdsm',
        ' APSCGYKKAUNEZGCPRDSM\n',
        'ＡＰＳＣＧ－ＹＫＫＡＵ　ｎｅｚｇｃ－ＰＲＤＳＭ',
        'apscg​ykkau-nezgc-prdsm',
      ]) {
        expect(_type('|', pasted), 'APSCG-YKKAU-NEZGC-PRDSM|', reason: pasted);
        expect(normalizeActivationCode(_v(_type('|', pasted)).text), 'APSCG-YKKAU-NEZGC-PRDSM');
      }
    });

    test('into the middle, the cursor lands after the pasted characters', () {
      expect(_type('ABCDE-|FGHIJ', 'kl-mn'), 'ABCDE-KLMN|F-GHIJ');
    });
  });

  group('e. replacing or deleting a selection', () {
    test('deleting a selection across a hyphen', () {
      expect(_backspace('ABC[DE-FG]HIJ'), 'ABC|HI-J');
    });

    test('replacing a selection', () {
      expect(_type('ABC[DE-FG]HIJ', 'x'), 'ABCX|H-IJ');
      expect(_type('[ABCDE-FGHIJ]', 'apscg-ykkau'), 'APSCG-YKKAU|');
    });

    test('deleting everything', () {
      expect(_backspace('[APSCG-YKKAU]'), '|');
    });

    test('a selection-only change keeps the selection on the same characters', () {
      expect(_format('ABCDE-FG|HIJ', 'ABCDE-[FG]HIJ'), 'ABCDE-[FG]HIJ');
    });
  });

  group('f. composing', () {
    test('text being composed passes through untouched', () {
      const composing = TextEditingValue(
        text: 'ABCDEf',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 5, end: 6),
      );
      expect(_formatter.formatEditUpdate(_v('ABCDE|'), composing), same(composing));
    });

    test('once composing ends the text is formatted', () {
      const committed = TextEditingValue(text: 'ABCDEf', selection: TextSelection.collapsed(offset: 6));
      expect(_marked(_formatter.formatEditUpdate(_v('ABCDEf|'), committed)), 'ABCDE-F|');
    });
  });

  test('no length limit', () {
    expect(_type('|', 'A' * 27), '${'AAAAA-' * 5}AA|');
  });
}
