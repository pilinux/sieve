#!/bin/sh
# Run Script phase: sets the built bundle's version to the tag on HEAD,
# without a leading v, else the first 7 characters of its hash.
# Outside a git checkout, the version from the build settings stays.
set -eu
cd "$SRCROOT"
version=$(git describe --tags --exact-match 2>/dev/null || git rev-parse HEAD | cut -c1-7) || exit 0
[ -n "$version" ] || exit 0
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version#v}" "$TARGET_BUILD_DIR/$INFOPLIST_PATH"
