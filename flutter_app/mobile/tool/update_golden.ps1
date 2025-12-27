# Powershell helper to capture golden images
# Usage (Powershell):
#  Set-Item -Path Env:UPDATE_GOLDENS -Value "true"
#  flutter test test/golden --update-goldens

Set-Item -Path Env:UPDATE_GOLDENS -Value "true"
flutter test test/golden --update-goldens
