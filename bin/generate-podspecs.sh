#!/bin/sh

# Exit if any command fails
set -e

# Change to the expected directory.
cd "$( dirname $0 )"
cd ..

# Check for cocoapods & jq
command -v pod > /dev/null || ( echo Cocoapods is required to generate podspecs; exit 1 )
command -v jq > /dev/null || ( echo jq is required to generate podspecs; exit 1 )

WD=$(pwd)
DEST="${WD}/third-party-podspecs"
NODE_MODULES_DIR="gutenberg/node_modules"

# Generate the external (non-RN podspecs)
EXTERNAL_PODSPECS=$(find "$NODE_MODULES_DIR/react-native/third-party-podspecs" \
                         "$NODE_MODULES_DIR/react-native-svg" \
                         "$NODE_MODULES_DIR/react-native-keyboard-aware-scroll-view" \
                         "$NODE_MODULES_DIR/react-native-safe-area" \
                         "$NODE_MODULES_DIR/react-native-dark-mode" \
                         "$NODE_MODULES_DIR/react-native-get-random-values" -type f -name "*.podspec" -print)

for podspec in $EXTERNAL_PODSPECS
do
    pod=$(basename "$podspec" .podspec)

    echo "Generating podspec for $pod"
    pod ipc spec $podspec > "$DEST/$pod.podspec.json"
done

# Generate the React Native podspecs
# Change to the React Native directory to get relative paths for the RN podspecs
cd "$NODE_MODULES_DIR/react-native"

RN_PODSPECS=$(find * -type f -name "*.podspec" -not -path "third-party-podspecs/*" -not -path "*Fabric*" -print)
TMP_DEST=$(mktemp -d)

for podspec in $RN_PODSPECS
do
    pod=$(basename "$podspec" .podspec)
    path=$(dirname "$podspec")

    echo "Generating podspec for $pod with path $path"
    pod ipc spec $podspec > "$TMP_DEST/$pod.podspec.json"
    cat "$TMP_DEST/$pod.podspec.json" | jq > "$DEST/$pod.podspec.json"

    # Add a "prepare_command" entry to each podspec so that 'pod install' will fetch sources from the correct directory
    # and retains the existing prepare_command if it exists
    prepare_command="TMP_DIR=\$(mktemp -d); mv * \$TMP_DIR; cp -R \"\$TMP_DIR/${path}\"/* ."
    cat "$TMP_DEST/$pod.podspec.json" | jq --arg CMD "$prepare_command" '.prepare_command = "\($CMD) && \(.prepare_command // true)"' > "$DEST/$pod.podspec.json"

    # FBReactNativeSpec needs special treatment because of react-native-codegen code generation
    if [[ "$pod" == "FBReactNativeSpec" ]]; then
        # First move it to its own folder
        mkdir -p "$DEST/FBReactNativeSpec/FBReactNativeSpec"
        mv "$DEST/FBReactNativeSpec.podspec.json" "$DEST/FBReactNativeSpec"

        # Then we generate FBReactNativeSpec-generated.mm and FBReactNativeSpec.h files.
        # They are normally generated during compile time using a Script Phase in FBReactNativeSpec added via the `use_react_native_codegen` function.
        # This script is inside node_modules/react-native/scripts folder. Since we don't have the node_modules when compiling WPiOS,
        # we're calling the script here manually to generate these files ahead of time.
        CODEGEN_MODULES_OUTPUT_DIR=$DEST/FBReactNativeSpec/FBReactNativeSpec ./scripts/generate-specs.sh 

        # Removing the Script Phase in FBReactNativeSpec Podfile that shouldn't be needed anymore.
        TMP_FBReactNativeSpec=$(mktemp)
        jq 'del(.script_phases)' "$DEST/FBReactNativeSpec/FBReactNativeSpec.podspec.json" > "$TMP_FBReactNativeSpec"

        # The prepare_command includes steps to create intermediate folders to keep generated files.
        # That shouldn't be needed anymore as well, so we're replacing the prepare_command entirely.
        cat "$TMP_FBReactNativeSpec" | jq --arg CMD "$prepare_command" '.prepare_command = "\($CMD)"' > "$DEST/FBReactNativeSpec/FBReactNativeSpec.podspec.json"
    fi
done
