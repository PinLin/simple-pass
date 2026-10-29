// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'SimplePASS';

  @override
  String get profileListEmpty => '尚無設定檔，點右下角「+」新增。';

  @override
  String profileCounterCompactLabel(int counter) {
    return '#$counter';
  }

  @override
  String get addProfileTooltip => '新增設定檔';

  @override
  String get addProfileTitle => '新增設定檔';

  @override
  String get fieldName => '名稱';

  @override
  String get fieldNameRequired => '請輸入名稱';

  @override
  String get fieldActivationCode => 'Activation Code';

  @override
  String get activationCodeHint => 'XXXXX-XXXXX-XXXXX-XXXXX';

  @override
  String get activationCodeRequired => '請輸入 Activation Code';

  @override
  String get activationCodeInvalid => 'Activation Code 格式不正確';

  @override
  String get activationCodePolicyMismatch =>
      'Activation Code 格式與 Policy String 版本不一致';

  @override
  String get regenerateActivationCodeTooltip => '重新產生 Activation Code';

  @override
  String get copyActivationCodeTooltip => '複製 Activation Code';

  @override
  String get copiedActivationCodeMessage => '已複製 Activation Code';

  @override
  String get fieldPolicy => 'Policy String';

  @override
  String get fieldPolicyOptional => 'Policy String（非必填）';

  @override
  String get policyInvalid => 'Policy String 格式不正確';

  @override
  String get policyUnsupportedVersion => '不支援此 Policy String 版本';

  @override
  String get policyUnsupportedOtpType => '不支援此 Policy String 的驗證碼類型';

  @override
  String codeRefreshCountdown(int seconds) {
    return '$seconds 秒後更新驗證碼';
  }

  @override
  String get fieldCounter => '計數器';

  @override
  String get counterInvalid => '計數器必須是不小於 0 的整數';

  @override
  String get saveButton => '儲存';

  @override
  String get cancelButton => '取消';

  @override
  String get markUsedButton => '標記已使用';

  @override
  String markedUsedMessage(int counter) {
    return '已標記 #$counter 為已使用';
  }

  @override
  String get undoButton => '復原';

  @override
  String get undoUnavailableMessage => '無法復原：計數器之後已被變更。';

  @override
  String get deleteProfileButton => '刪除';

  @override
  String deleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '刪除設定檔？',
    );
    return '$_temp0';
  }

  @override
  String get deleteConfirmButton => '刪除';

  @override
  String get openSourceLicensesLabel => '開放原始碼授權';

  @override
  String get settingsTitle => '設定';

  @override
  String get authNotAvailableMessage => '這台裝置尚未設定指紋、臉部或裝置密碼。';

  @override
  String get authFailedMessage => '身分驗證失敗';

  @override
  String counterTooLarge(int max) {
    return '計數器不可超過 $max';
  }

  @override
  String get authCanceledMessage => '已取消身分驗證';

  @override
  String get authLockedOutMessage => '嘗試次數過多，請稍後再試。';

  @override
  String get loadErrorMessage => '無法讀取已儲存的資料。在成功讀取之前，不會做任何修改。';

  @override
  String get retryButton => '重試';

  @override
  String get saveFailedMessage => '無法儲存變更';

  @override
  String get copyCodeAction => '複製驗證碼';

  @override
  String get fieldPin => 'PIN';

  @override
  String pinHint(int min, int max) {
    return '選填，$min～$max 位數字';
  }

  @override
  String pinInvalid(int min, int max) {
    return 'PIN 必須是 $min～$max 位數字';
  }

  @override
  String get appendPinOnCopyLabel => '複製時加上 PIN';

  @override
  String get appendPinOnCopySubtitle => '複製內容為 PIN 接著驗證碼';

  @override
  String get copiedPinAndCodeMessage => '已複製 PIN＋驗證碼';

  @override
  String get copiedCodeMessage => '已複製驗證碼';

  @override
  String get clipboardClearLabel => '自動清除剪貼簿';

  @override
  String get clipboardClearNever => '不清除';

  @override
  String clipboardClearSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String clipboardClearMinutes(int minutes) {
    return '$minutes 分鐘';
  }

  @override
  String get unlockButton => '解鎖';

  @override
  String get editButton => '編輯';

  @override
  String get keysInvalidatedMessage => '手機螢幕鎖曾被移除，需要驗證身分的設定檔已永久無法解開，只能刪除。';

  @override
  String get deleteUnrecoverableButton => '刪除這些設定檔';

  @override
  String get requireAuthLabel => '開啟 App 時需要驗證身分';

  @override
  String get requireAuthSubtitle => '以指紋、臉部或螢幕鎖定解鎖';

  @override
  String get requireAuthWarningMessage =>
      '之後若移除手機的螢幕鎖定，受保護的設定檔將無法解開，只能刪除。建議另外保存 Activation Code 與私密金鑰（或該服務的復原碼）；以 Enrollment String 註冊的設定檔屆時需要新的 Enrollment String 重新註冊。';

  @override
  String get requireAuthConfirmButton => '開啟';

  @override
  String get challengeCodeLabel => 'Challenge Code';

  @override
  String challengeCodeHint(int length) {
    return '請輸入 $length 位數字';
  }

  @override
  String get enterChallengeCodeAction => '輸入 Challenge Code';

  @override
  String get okButton => '確定';

  @override
  String get addKindActivationCodeSubtitle => '產生或輸入 Activation Code';

  @override
  String get addKindEnrollmentString => 'MobilePASS 自動註冊';

  @override
  String get addKindEnrollmentStringSubtitle => '輸入 Enrollment String';

  @override
  String get enrollTitle => 'MobilePASS 自動註冊';

  @override
  String get fieldEnrollmentString => 'Enrollment String';

  @override
  String get enrollmentStringRequired => '請輸入 Enrollment String';

  @override
  String get enrollmentStringInvalid => 'Enrollment String 格式不正確';

  @override
  String get enrollmentStringNotHttps => '註冊伺服器必須使用 https';

  @override
  String get pasteFromClipboardTooltip => '從剪貼簿貼上';

  @override
  String get clipboardEmptyMessage => '剪貼簿裡沒有文字';

  @override
  String enrollServerLabel(String host) {
    return '將向 $host 註冊';
  }

  @override
  String get fieldUserId => '使用者 ID';

  @override
  String get userIdRequired => '請輸入使用者 ID';

  @override
  String get fieldPassphrase => 'Passphrase';

  @override
  String get passphraseRequired => '請輸入 Passphrase';

  @override
  String get enrollButton => '註冊';

  @override
  String get enrollStepContacting => '正在連線到伺服器…';

  @override
  String get enrollStepRegistering => '正在註冊…';

  @override
  String get otpPinTitle => '設定 OTP PIN';

  @override
  String otpPinMessage(int min, int max) {
    return '請設定 $min～$max 位數字的 PIN。';
  }

  @override
  String otpPinMessageAlphanumeric(int min, int max) {
    return '請設定 $min～$max 位英數字的 PIN。';
  }

  @override
  String get otpPinInvalid => 'PIN 不符合格式要求';

  @override
  String get continueButton => '繼續';

  @override
  String get enrollErrorNetwork => '無法連線到註冊伺服器，請確認網路連線後再試一次。';

  @override
  String enrollErrorHttp(String status) {
    return '註冊伺服器回應 HTTP $status。';
  }

  @override
  String get enrollErrorBadResponse => '伺服器的回應不是有效的註冊回應。';

  @override
  String enrollErrorRejected(String status) {
    return '伺服器拒絕註冊（$status）。請確認使用者 ID 與 Passphrase，或向管理者索取新的 Enrollment String。';
  }

  @override
  String get enrollErrorMac => '伺服器的金鑰確認未通過，未儲存任何資料。';

  @override
  String get enrollErrorPolicy =>
      '伺服器提供的 Policy String 不受支援。伺服器端可能已完成註冊，請管理者重新發送 Enrollment String。';

  @override
  String get enrollSaveFailedMessage => '已完成註冊，但無法儲存設定檔。請點「儲存」再試一次。';

  @override
  String get fieldSerial => '序號';

  @override
  String get profileKeyInvalid => '儲存的金鑰無效';

  @override
  String get enrollErrorCertificate => '無法驗證註冊伺服器的憑證。';

  @override
  String get addKindTotpSubtitle => '掃描 QR Code 或輸入私密金鑰';

  @override
  String get fieldSecret => '私密金鑰';

  @override
  String get secretRequired => '請輸入私密金鑰';

  @override
  String get secretInvalid => '私密金鑰不是有效的 Base32';

  @override
  String get copiedSecretMessage => '已複製私密金鑰';

  @override
  String get scanQrButton => '掃描 QR Code';

  @override
  String get importQrPhotoButton => '從相片匯入';

  @override
  String get scanQrTitle => '掃描 QR Code';

  @override
  String get cameraUnavailableMessage => '無法啟動相機。請改用「從相片匯入」，或手動輸入私密金鑰。';

  @override
  String get cameraPermissionDeniedMessage => '掃描需要相機權限，仍可手動輸入私密金鑰。';

  @override
  String get cameraPermissionBlockedMessage =>
      'SimplePASS 的相機權限已關閉。如要掃描，請到系統設定開啟；也可以手動輸入私密金鑰。';

  @override
  String get openSettingsButton => '開啟設定';

  @override
  String get qrNotFoundMessage => '這張相片裡找不到 QR Code';

  @override
  String get otpauthImportedMessage => '已從連結帶入設定';

  @override
  String get otpauthNotLinkMessage => '這不是 otpauth:// 連結';

  @override
  String get otpauthMigrationMessage =>
      '不支援 Google Authenticator 的匯出 QR Code（otpauth-migration://），請改用各帳號個別的 QR Code。';

  @override
  String get otpauthUnsupportedTypeMessage => '只支援 TOTP 與 HOTP 連結';

  @override
  String get otpauthInvalidSecretMessage => '連結中的金鑰缺漏或無效';

  @override
  String get otpauthUnsupportedParametersMessage =>
      '連結使用了本 App 不支援的演算法、位數、週期或計數器';

  @override
  String get cameraNotFoundMessage => '找不到可用的相機。請改用「從相片匯入」，或手動輸入私密金鑰。';

  @override
  String get scanBackButton => '返回';

  @override
  String get addKindActivationCode => 'MobilePASS 手動註冊';

  @override
  String get otpauthEnrollmentStringMessage =>
      '這是 Enrollment String，請改用「MobilePASS 自動註冊」新增。';

  @override
  String get tapToRevealLabel => '點一下才顯示驗證碼';

  @override
  String get tapToRevealSubtitle => '驗證碼以圓點遮住，點一下設定檔才會顯示';

  @override
  String get revealCodeAction => '顯示並複製驗證碼';

  @override
  String selectedCount(int count) {
    return '已選取 $count 個';
  }

  @override
  String get selectAction => '選取';

  @override
  String deleteSelectedConfirmMessage(int count) {
    return '這會永久刪除 $count 個設定檔。';
  }

  @override
  String get deselectAction => '取消選取';

  @override
  String get parameterTimeBased => '依時間產生';

  @override
  String get parameterCounterBased => '依計數器產生';

  @override
  String parameterDigits(int digits) {
    return '$digits 位數';
  }

  @override
  String get protectedProfilesBanner => '已關閉驗證身分，但仍有設定檔受保護。';

  @override
  String get unprotectNowButton => '解除保護';

  @override
  String get appLockedMessage => 'SimplePASS 已鎖定';

  @override
  String get allowScreenshotsLockNote =>
      'App 鎖開啟時，Android 12 以下一律禁止截圖，以免最近使用的應用程式畫面露出內容。';

  @override
  String get blockScreenshotsLabel => '禁止螢幕截圖';

  @override
  String get blockScreenshotsSubtitle => '防止其他 App 取得螢幕畫面';

  @override
  String get showSecretTooltip => '顯示';

  @override
  String get hideSecretTooltip => '隱藏';

  @override
  String challengeCodeSemanticsLabel(String code) {
    return 'Challenge Code $code';
  }

  @override
  String get unsavedChangesTitle => '有未儲存的內容';

  @override
  String get discardButton => '捨棄';

  @override
  String get keepEditingButton => '繼續編輯';

  @override
  String get typeStandardTotp => 'TOTP';

  @override
  String get typeStandardHotp => 'HOTP';

  @override
  String get typeChallengeResponse => '挑戰回應';

  @override
  String get notSetValue => '未設定';

  @override
  String get copiedEquivalentLinkMessage => '已複製連結';

  @override
  String get copyOtpauthLinkButton => '複製 otpauth 連結';

  @override
  String get moreOptionsTooltip => '更多選項';

  @override
  String get copiedFieldMessage => '已複製';

  @override
  String get copyFieldTooltip => '複製';

  @override
  String get otpChallengeLengthLabel => 'Challenge Code 長度';

  @override
  String get otpTypeLabel => '驗證碼種類';

  @override
  String get otpDigitsLabel => '驗證碼位數';

  @override
  String get otpAlgorithmLabel => '演算法';

  @override
  String get otpPeriodLabel => '更新週期（秒）';

  @override
  String get otpPeriodInvalid => '請輸入 1 至 3600 秒的週期';

  @override
  String get deleteProfileMessage => '要從此手機刪除這個設定檔嗎？這不會解除伺服器端的驗證設定。';

  @override
  String profileDetailsTitle(String type, String spacing) {
    String _temp0 = intl.Intl.selectLogic(spacing, {
      'cjk': '$type設定檔',
      'other': '$type 設定檔',
    });
    return '$_temp0';
  }

  @override
  String get openCameraButton => '開啟相機';

  @override
  String get addKindTotpMenuTitle => '手動新增';

  @override
  String get mobilePassFormatLabel => '使用 MobilePASS 規格';

  @override
  String get registrationInfoMenuItem => 'MobilePASS 註冊資訊';

  @override
  String get mobilePassFormatLine => 'MobilePASS 規格';

  @override
  String get addTotpScreenTitle => '手動新增';
}
