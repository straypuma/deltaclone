#!/bin/zsh
# Builds Folio.app (Apple Silicon, release) with Xcode.
#   ./build.sh            → build/Folio.app
#   ./build.sh --install  → also copies it to /Applications
#   ./build.sh --test     → runs the UI tests instead
set -euo pipefail
cd "${0:A:h}"

if [[ "${1:-}" == "--test" ]]; then
  exec xcodebuild test -project Folio.xcodeproj -scheme Folio -destination "platform=macOS,arch=arm64" \
    -derivedDataPath build/DerivedData -quiet
fi

xcodebuild build -project Folio.xcodeproj -scheme Folio -configuration Release \
  -destination "platform=macOS,arch=arm64" -derivedDataPath build/DerivedData -quiet

rm -rf build/Folio.app
cp -R build/DerivedData/Build/Products/Release/Folio.app build/Folio.app
echo "Built build/Folio.app ($(du -sh build/Folio.app | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
  if pgrep -xq Folio; then
    osascript -e 'tell application "Folio" to quit'
    sleep 1
  fi
  rm -rf /Applications/Folio.app
  cp -R build/Folio.app /Applications/
  # Register the app and its widget with the system right away.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Folio.app
  echo "Installed to /Applications/Folio.app"
fi
