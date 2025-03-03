#!/bin/bash -eu

echo '--- :node: Setup Node depenendencies'
npm ci --unsafe-perm --prefer-offline --no-audit --no-progress

echo '--- :ios: Set env var for iOS E2E testing'
set -x
export TEST_RN_PLATFORM=ios
export TEST_ENV=sauce
CONFIG_FILE="$(pwd)/gutenberg/packages/react-native-editor/__device-tests__/helpers/device-config.json"
# Uses the local deviceName since SauceLabs uses a different one.
IOS_DEVICE_NAME=$(jq -r '.ios.local.deviceName' "$CONFIG_FILE")
IOS_PLATFORM_VERSION=$(jq -r '.ios.buildkite.platformVersion' "$CONFIG_FILE")
# Set a destination different from the hardcoded one which only works in the
# older Xcode-setup used by CircleCI
export RN_EDITOR_E2E_IOS_DESTINATION="platform=iOS Simulator,name=$IOS_DEVICE_NAME,OS=$IOS_PLATFORM_VERSION"
set +x

echo '--- :react: Build iOS app for E2E testing'
npm run core test:e2e:build-app:ios

echo '--- :react: Build iOS bundle for E2E testing'
npm run test:e2e:bundle:ios

echo '--- :compression: Prepare artifact for SauceLabs upload'
WORK_DIR=$(pwd) \
  && pushd ./gutenberg/packages/react-native-editor/ios/build/GutenbergDemo/Build/Products/Release-iphonesimulator \
  && zip -r "$WORK_DIR/gutenberg/packages/react-native-editor/ios/GutenbergDemo.app.zip" GutenbergDemo.app \
  && popd

echo '--- :saucelabs: Upload app artifact to SauceLabs'
SAUCE_FILENAME=${BUILDKITE_BRANCH//[\/]/-}
curl -u "$SAUCE_USERNAME:$SAUCE_ACCESS_KEY" \
  --location \
  --request POST 'https://api.us-west-1.saucelabs.com/v1/storage/upload' \
  --form 'payload=@"./gutenberg/packages/react-native-editor/ios/GutenbergDemo.app.zip"' \
  --form "name=Gutenberg-$SAUCE_FILENAME.app.zip" \
  --form 'description="Gutenberg"'
