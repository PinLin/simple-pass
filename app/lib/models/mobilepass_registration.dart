/// The inputs actually used for a successful MobilePASS auto enrollment. All fields are sensitive;
/// the original string may contain additional server-specific fields and is kept intact.
class MobilePassRegistration {
  const MobilePassRegistration({
    required this.enrollmentString,
    required this.url,
    required this.userId,
    required this.passphrase,
  });

  final String enrollmentString;
  final String url;
  final String userId;
  final String passphrase;

  factory MobilePassRegistration.fromJson(Map<String, dynamic> json) => MobilePassRegistration(
    enrollmentString: json['enrollmentString'] as String,
    url: json['url'] as String,
    userId: json['userId'] as String,
    passphrase: json['passphrase'] as String,
  );

  Map<String, dynamic> toJson() => {
    'enrollmentString': enrollmentString,
    'url': url,
    'userId': userId,
    'passphrase': passphrase,
  };

  @override
  bool operator ==(Object other) =>
      other is MobilePassRegistration &&
      enrollmentString == other.enrollmentString &&
      url == other.url &&
      userId == other.userId &&
      passphrase == other.passphrase;

  @override
  int get hashCode => Object.hash(enrollmentString, url, userId, passphrase);
}
