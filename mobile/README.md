# Lynveris Flutter

Android app and web preview use the same Flutter UI. See [installation and API setup](../README.md), [data and model](../docs/data-and-model.md) and [verification](../docs/verification.md).

Use Flutter 3.47.4 and its bundled Dart SDK. Set `API_BASE_URL` with `--dart-define` or change the backend address in the app's settings. Android Emulator uses `http://10.0.2.2:8000`. The app allows public backends only over HTTPS.

Clipboard reads, URL checks, third party lookups, history and sharing are user initiated. There is no mocked API or bundled pretend model in this application.
