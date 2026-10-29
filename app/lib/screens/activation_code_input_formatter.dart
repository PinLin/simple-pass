import 'package:flutter/services.dart';

import '../mobilepass/activation_code.dart';

/// Keeps an activation code field in the form [normalizeActivationCode] saves: uppercase letters and digits
/// in groups of five joined by '-'. The cursor stays after the same number of code characters it was after, and deleting a
/// lone '-' deletes the code character on the far side of it instead, so the '-' cannot reappear in place.
class ActivationCodeInputFormatter extends TextInputFormatter {
  const ActivationCodeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) return newValue;

    final text = newValue.text;
    var chars = _codeCharacters(text);
    final selection = newValue.selection;
    var base = selection.isValid ? _countBefore(text, selection.baseOffset) : chars.length;
    var extent = selection.isValid ? _countBefore(text, selection.extentOffset) : chars.length;

    final old = oldValue.selection;
    final removedOnlyOneHyphen =
        old.isValid &&
        selection.isCollapsed &&
        text.length == oldValue.text.length - 1 &&
        chars == _codeCharacters(oldValue.text);
    if (removedOnlyOneHyphen) {
      // A selected '-' that gets deleted counts as a backspace too.
      final backspace = !old.isCollapsed || selection.baseOffset == old.baseOffset - 1;
      if (backspace && base > 0) {
        chars = chars.substring(0, base - 1) + chars.substring(base);
        base = extent = base - 1;
      } else if (old.isCollapsed && selection.baseOffset == old.baseOffset && base < chars.length) {
        chars = chars.substring(0, base) + chars.substring(base + 1);
      }
    }

    final formatted = normalizeActivationCode(chars);
    if (base == extent) {
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: _offsetAfter(base)),
      );
    }
    // A selection starts before its first code character and ends after its last, hyphens aside.
    final forward = base < extent;
    final start = _offsetBefore(forward ? base : extent, chars.length);
    final end = _offsetAfter(forward ? extent : base);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection(baseOffset: forward ? start : end, extentOffset: forward ? end : start),
    );
  }

  static String _codeCharacters(String text) => activationCodeCharacters(_toHalfWidth(text));

  static int _countBefore(String text, int offset) =>
      _codeCharacters(text.substring(0, offset.clamp(0, text.length))).length;

  // Right after the [count]th code character, before any '-' that follows it.
  static int _offsetAfter(int count) => count == 0 ? 0 : count + (count - 1) ~/ 5;

  // Right before the code character after the first [count], past any '-' in between.
  static int _offsetBefore(int count, int total) => count >= total ? _offsetAfter(count) : count + count ~/ 5;

  // Codes typed with a CJK input method or pasted from CJK text can arrive as full-width forms.
  static String _toHalfWidth(String text) => String.fromCharCodes(
    text.codeUnits.map((c) => c >= 0xFF01 && c <= 0xFF5E ? c - 0xFEE0 : (c == 0x3000 ? 0x20 : c)),
  );
}
