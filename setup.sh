#!/usr/bin/env bash
# Generates the remaining Android/Gradle scaffolding (existing files are kept)
# and fetches packages. Requires Flutter + Android SDK (`flutter doctor`).
set -euo pipefail
cd "$(dirname "$0")"
flutter create --org com.sphurthy --project-name gps_camera --platforms android .
flutter pub get
echo
echo "Ready. Plug in a phone (USB debugging on) and run:  flutter run"
echo "Release APK:  flutter build apk --release --split-per-abi"
