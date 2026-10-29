import 'dart:convert';

/// Why [parseEnrollmentString] rejected its input.
enum EnrollmentStringError {
  /// Not Base64, or the decoded text has no EnrollmentURL.
  invalidFormat,

  /// The EnrollmentURL isn't an https URL with a host.
  notHttps,
}

class EnrollmentStringException implements Exception {
  const EnrollmentStringException(this.error);

  final EnrollmentStringError error;

  @override
  String toString() => 'EnrollmentStringException(${error.name})';
}

/// A decoded Enrollment String. [userId] and [passphrase] are empty when the string leaves them out,
/// and must then be asked for.
class EnrollmentString {
  const EnrollmentString({required this.url, this.userId = '', this.passphrase = ''});

  /// Exactly as given: it is also an input to the authentication MAC.
  final String url;
  final String userId;
  final String passphrase;

  Uri get uri => Uri.parse(url);

  EnrollmentString copyWith({String? userId, String? passphrase}) =>
      EnrollmentString(url: url, userId: userId ?? this.userId, passphrase: passphrase ?? this.passphrase);
}

/// Decodes Base64 of `EnrollmentURL=…\r\nUserID=…\r\nPassphrase=…`. Whitespace in the pasted text
/// and trailing NUL bytes in the decoded text are ignored. Throws [EnrollmentStringException].
EnrollmentString parseEnrollmentString(String input) {
  final compact = input.replaceAll(RegExp(r'\s'), '');
  String text;
  try {
    text = utf8.decode(base64.decode(base64.normalize(compact)), allowMalformed: true);
  } on FormatException {
    throw const EnrollmentStringException(EnrollmentStringError.invalidFormat);
  }
  text = text.replaceFirst(RegExp(r'\x00+$'), '');

  final fields = <String, String>{};
  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    fields.putIfAbsent(line.substring(0, eq).trim(), () => line.substring(eq + 1));
  }
  final url = fields['EnrollmentURL'];
  if (url == null || url.isEmpty) throw const EnrollmentStringException(EnrollmentStringError.invalidFormat);
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    throw const EnrollmentStringException(EnrollmentStringError.notHttps);
  }
  return EnrollmentString(url: url, userId: fields['UserID'] ?? '', passphrase: fields['Passphrase'] ?? '');
}
