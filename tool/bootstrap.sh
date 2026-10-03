#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --platforms=android --project-name=controle_led --org=com.fluttersupermauz .
cp tool/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
# Prevent the generated starter test from shadowing our prototype tests.
rm -f test/widget_test.dart
flutter pub get
