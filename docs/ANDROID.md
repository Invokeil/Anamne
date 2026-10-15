# Android

## Install

Download the arm64 APK from the project GitHub Release and transfer it to your device. Open it with the package installer and allow installation from that source if Android asks. The release-mode APK may be development-signed; it is suitable for evaluation, not Play Store distribution. Installing over a build signed with a different key may fail. Export or back up your workspace before changing installations.

The supplied build targets Android arm64. It is not suitable for devices that only support 32-bit ARM or x86. An Android phone or tablet is required; the desktop emulator is optional.

## First run and local data

Anamne stores workspace data locally on the device. Use the app's export/backup action before uninstalling, clearing app data, or replacing a differently signed build. Do not assume uninstall preserves notes.

## Optional self-hosted sync

Open Settings, enter the HTTPS URL of your Anamne API and an API token with the required role, select **Test**, then **Save & sync**. A phone cannot use the laptop's `localhost` address to reach a server on that laptop; use a reachable LAN hostname/IP for local testing, or a public HTTPS hostname. Do not expose an unauthenticated API to the internet.

## Troubleshooting

- If Android blocks the APK, approve installation for the file manager/browser used to open it.
- If installation reports a signature conflict, back up/export data before uninstalling the prior package; uninstalling may erase its local data.
- If sync fails, check the URL, token, device connectivity, server logs and CORS/TLS configuration. Never paste a private token into an issue.
- Bengali keyboard, selection, lifecycle and real-device behavior should be tested on the target device; desktop tests do not verify those behaviors.
