#!/bin/zsh
# Builds Folio.app (Apple Silicon, release) with Xcode.
#   ./build.sh                  → build/Folio.app
#   ./build.sh --install        → also copies it to /Applications
#   ./build.sh --dmg            → also packages build/Folio.dmg to send to someone
#   ./build.sh --release 1.2    → publishes version 1.2 as a GitHub release; installed copies
#                                 pick it up through Sparkle (Folio ▸ Check for Updates…)
#   ./build.sh --test           → runs the UI tests; results are kept (build/LastTestRun.xcresult)
#                                 only if one fails
#
# Build caches live in Xcode's usual DerivedData folder (shared with building inside Xcode),
# so this folder stays small. Signing uses the Apple ID added in Xcode ▸ Settings ▸ Accounts;
# updates are signed with the Sparkle key in your login keychain.
set -euo pipefail
cd "${0:A:h}"

mode=${1:-}
REPO=straypuma/deltaclone

XCODEBUILD=(xcodebuild -project Folio.xcodeproj -scheme Folio -destination "platform=macOS,arch=arm64"
            -allowProvisioningUpdates COMPILER_INDEX_STORE_ENABLE=NO -quiet)

products=$(xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
derived=${products:h:h:h}  # …/DerivedData/Folio-<hash>

# Xcode never prunes its logs; drop anything older than two weeks.
[[ -d "$derived/Logs" ]] && find "$derived/Logs" -type f -mtime +14 -delete 2>/dev/null

if [[ $mode == --test ]]; then
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

# Version: the release being published, else the latest release tag. The build number is the
# commit count, so every build is newer than the last and Sparkle can compare them.
if [[ $mode == --release ]]; then
  version=${2:?"usage: ./build.sh --release <version>, e.g. 1.2"}
  [[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes before releasing."; exit 1; }
  git rev-parse -q --verify "refs/tags/v$version" >/dev/null && { echo "v$version already exists."; exit 1; }
else
  version=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
  version=${version:-1.0}
fi
build_number=$(git rev-list --count HEAD)

"${XCODEBUILD[@]}" build -configuration Release MARKETING_VERSION=$version CURRENT_PROJECT_VERSION=$build_number

mkdir -p build
rm -rf build/Folio.app
cp -R "$products/Folio.app" build/Folio.app
echo "Built build/Folio.app $version ($build_number), $(du -sh build/Folio.app | cut -f1)"

make_dmg() {
  local stage=$(mktemp -d)
  cp -R build/Folio.app "$stage/"
  ln -s /Applications "$stage/Applications"
  rm -f "$1"
  hdiutil create -volname Folio -srcfolder "$stage" -format UDZO -quiet "$1"
  rm -rf "$stage"
}

if [[ $mode == --dmg ]]; then
  make_dmg build/Folio.dmg
  echo "Packaged build/Folio.dmg ($(du -h build/Folio.dmg | cut -f1))"
fi

if [[ $mode == --release ]]; then
  sparkle="$derived/SourcePackages/artifacts/sparkle/Sparkle/bin"
  rm -rf build/release && mkdir -p build/release
  make_dmg "build/release/Folio-$version.dmg"
  # Signs the DMG with the Sparkle key from the keychain and writes appcast.xml next to it.
  "$sparkle/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/v$version/" build/release
  git tag "v$version"
  git push -q origin "v$version"
  gh release create "v$version" "build/release/Folio-$version.dmg" build/release/appcast.xml \
    --repo "$REPO" --title "Folio $version" --generate-notes
  echo "Released Folio $version: https://github.com/$REPO/releases/tag/v$version"
fi

if [[ $mode == --install ]]; then
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
