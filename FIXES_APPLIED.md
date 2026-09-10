# LANtern Repair Pass

The repository has been repaired against the static audit. See `BUGS_FOUND.txt` for the complete defect list, fixes, and remaining architecture/security limitations.

## CI

`.github/workflows/android-apk.yml` now runs dependency installation, static analysis, tests, and a debug APK build. The APK is uploaded as a GitHub Actions artifact.

## Verification

Flutter/Dart are not installed in the repair environment, so the final `flutter analyze`, `flutter test`, and `flutter build apk` commands must execute in GitHub Actions or a local Flutter environment.
