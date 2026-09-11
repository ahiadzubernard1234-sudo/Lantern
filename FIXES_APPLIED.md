# LANtern Repair Pass

The repository has been repaired against the static audit. See `BUGS_FOUND.txt` for the complete defect list, fixes, and remaining architecture/security limitations.

## Continuation Repair Pass

The following defects were fixed after validating the archived project:

- Database upgrades from pre-V2 schemas now create the `peers` table before creating its indexes.
- Fresh database creation now creates indexes for peers and file transfers consistently with upgrades.
- The V2 connection manager now owns and cancels its server socket subscription during shutdown.
- The V2 discovery service now owns and cancels its datagram subscription, and its shutdown ordering no longer skips timer/socket cleanup.
- Channel creation no longer double-counts the owner, duplicate joins no longer inflate membership counts, and removing a non-member no longer decrements the count.

The legacy V1 network transport remains in place because the current chat and channel repositories still import it; deleting it would make the project fail to compile. V2 startup is currently profile-driven in `AppShell`, which avoids initializing the network with placeholder identity data before onboarding completes.

## CI

`.github/workflows/android-apk.yml` now runs dependency installation, static analysis, tests, and a debug APK build. The APK is uploaded as a GitHub Actions artifact.

## Verification

Flutter/Dart are not installed in the repair environment, so the final `flutter analyze`, `flutter test`, and `flutter build apk` commands must execute in GitHub Actions or a local Flutter environment. Repository-level XML and source checks pass after this continuation pass.
