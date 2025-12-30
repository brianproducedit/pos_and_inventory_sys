# mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


flutter pub run build_runner build --delete-conflicting-outputs

Next steps (optional):

Make the proxy persistent for future shells:

setx HTTP_PROXY "http://192.168.49.1:8282"
setx HTTPS_PROXY "http://192.168.49.1:8282"
setx NO_PROXY "localhost,127.0.0.1"
Note: setx affects new shells only.

Push-Location 'c:/Users/k.off/Documents/Programming/Programming Projects/Flutter/pos_and_inventory_sys/flutter_app/mobile'; $env:HTTP_PROXY='http://192.168.49.1:8282'; $env:HTTPS_PROXY='http://192.168.49.1:8282'; $env:NO_PROXY='localhost,127.0.0.1'; flutter pub get --no-precompile; Pop-Location

Push-Location 'c:/Users/k.off/Documents/Programming/Programming Projects/Flutter/pos_and_inventory_sys/flutter_app/mobile'; $env:HTTP_PROXY='http://192.168.49.1:8282'; $env:HTTPS_PROXY='http://192.168.49.1:8282'; $env:PUB_HOSTED_URL=''; $env:FLUTTER_STORAGE_BASE_URL=''; flutter pub get --verbose; Pop-Location