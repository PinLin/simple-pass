import 'package:flutter/foundation.dart';

const androidApache2Packages = ['androidx.appcompat', 'androidx.biometric', 'FreeDroidWarn'];

const _apache2Notice =
    'Licensed under the Apache License, Version 2.0. You may obtain a copy of the License at\n\n'
    'https://www.apache.org/licenses/LICENSE-2.0\n\n'
    'Unless required by applicable law or agreed to in writing, software distributed under the License is '
    'distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.';

/// Flutter only collects Dart package licenses; these are the Android (Gradle) dependencies.
void registerAndroidLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(androidApache2Packages, _apache2Notice);
  });
}
