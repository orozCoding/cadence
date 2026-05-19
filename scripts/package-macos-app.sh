#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Cadence.xcodeproj"
SCHEME="Cadence"
CONFIGURATION="Release"
BUILD_DIR="${ROOT_DIR}/dist/build"
OUTPUT_DIR="${ROOT_DIR}/dist/release"
APP_PATH="${BUILD_DIR}/Cadence.app"
ZIP_PATH="${OUTPUT_DIR}/Cadence-macOS.zip"
RESULT_BUNDLE_PATH="${ROOT_DIR}/.build/Cadence.xcresult"

rm -rf "${BUILD_DIR}" "${OUTPUT_DIR}" "${RESULT_BUNDLE_PATH}"
mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${ROOT_DIR}/.build/DerivedData" \
  -resultBundlePath "${RESULT_BUNDLE_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CONFIGURATION_BUILD_DIR="${BUILD_DIR}" \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected app bundle was not created at ${APP_PATH}" >&2
  exit 1
fi

xattr -cr "${APP_PATH}"
ditto -c -k --keepParent --norsrc "${APP_PATH}" "${ZIP_PATH}"

echo "Created ${ZIP_PATH}"
