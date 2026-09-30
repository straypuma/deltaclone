#!/bin/zsh
# Builds Folio.app (Apple Silicon, release) with Xcode.
#   ./build.sh            → build/Folio.app
#   ./build.sh --install  → also copies it to /Applications
#   ./build.sh --dmg      → also packages build/Folio.dmg to send to someone
#   ./build.sh --test     → runs the UI tests; results are kept (build/LastTestRun.xcresult) only if one fails
#
# Build caches live in Xcode's usual DerivedData folder (shared with building inside Xcode),
# so this folder stays small. Signing uses the Apple ID added in Xcode ▸ Settings ▸ Accounts.
set -euo pipefail
cd "${0:A:h}"

XCODEBUILD=(xcodebuild -project Folio.xcodeproj -scheme Folio -destination "platform=macOS,arch=arm64"
            -allowProvisioningUpdates COMPILER_INDEX_STORE_ENABLE=NO -quiet)

products=$(xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
derived=${products:h:h:h}  # …/DerivedData/Folio-<hash>

# Xcode never prunes its logs; drop anything older than two weeks.
[[ -d "$derived/Logs" ]] && find "$derived/Logs" -type f -mtime +14 -delete 2>/dev/null

if [[ "${1:-}" == "--test" ]]; then
  mkdir -p build
  rm -rf build/LastTestRun.xcresult
  result=0
  # Build separately so the kept result holds test results only, not a full build log.
  "${XCODEBUILD[@]}" build-for-testing
  "${XCODEBUILD[@]}" test-without-building -resultBundlePath build/LastTestRun.xcresult || result=$?
  # Xcode also keeps its own copy of every run's logs; the one above is enough.
  rm -rf "$derived/Logs/Test"
  if (( result == 0 )); then
    passed=$(xcrun xcresulttool get test-results summary --path build/LastTestRun.xcresult 2>/dev/null \
      | awk -F': ' '/"passedTests"/{gsub(/[ ,]/, "", $2); print $2; exit}')
    # A passing run's results (mostly symbol data for crash reports) are ~200 MB of nothing useful.
    rm -rf build/LastTestRun.xcresult
    echo "All ${passed:-} tests passed."
  else
    echo "Tests failed. Details: open build/LastTestRun.xcresult in Xcode."
  fi
  exit $result
fi

"${XCODEBUILD[@]}" build -configuration Release

mkdir -p build
rm -rf build/Folio.app
cp -R "$products/Folio.app" build/Folio.app
echo "Built build/Folio.app ($(du -sh build/Folio.app | cut -f1))"

if [[ "${1:-}" == "--dmg" ]]; then
  stage=$(mktemp -d)
  cp -R build/Folio.app "$stage/"
  ln -s /Applications "$stage/Applications"
  rm -f build/Folio.dmg
  hdiutil create -volname Folio -srcfolder "$stage" -format UDZO -quiet build/Folio.dmg
  rm -rf "$stage"
  echo "Packaged build/Folio.dmg ($(du -h build/Folio.dmg | cut -f1))"
fi

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
