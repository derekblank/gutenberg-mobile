#!/bin/bash
# 
# The I18n update command handles the process of updating the i18n localizations of plugins 
# including Gutenberg. The main goals of this command are:
#
#   1. Download translation files and optimize them by filtering out the unused strings,
#      previously extracted from the React Native bundle.
#
#      This step produces the following output files:
#      - src/i18n-cache/{PLUGIN_NAME}/data/{LOCALE}.json     [Translation files]
#      - src/i18n-cache/{PLUGIN_NAME}/data/index.native.json [JS file to import translations]
#
#   2. Generate localization strings files that include the strings only used in "*.native.js"
#      source code files. The translations of these strings are not included in the GlotPress projects 
#      of their plugins hence, they require to be requested as part of the main apps’ strings.
#
#      This step produces the following output files:
#      - bundle/android/strings.xml                     [Localization strings files for Android platform]
#      - bundle/ios/GutenbergNativeTranslations.swift   [Localization strings files for iOS platform]

# Exit if any command fails
set -e

# Get arguments
while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo "options:"
      echo "-h, --help                              show brief help"
      echo "-w, --skip-upgrade-wp-cli               skip WP-CLI upgrade"
      echo "-g, --skip-gutenberg-build              skip Gutenberg build"
      echo "-p, --use-local-path                    use local path for generating files"
      echo "-u, --skip-extract-used-strings         skip extract used strings"
      echo "-t, --skip-download-translations        skip translation download"
      echo "-l, --skip-localization-strings-files   skip generate localization strings files"
      echo "-d, --debug                             print extra info for debugging"
      exit 0
      ;;
    -w|--skip-upgrade-wp-cli*)
      shift
      SKIP_UPGRADE_WP_CLI='true'
      ;;
    -g|--skip-gutenberg-build*)
      shift
      SKIP_GUTENGERG_BUILD='true'
      ;;
    -p|--use-local-path*)
      shift
      USE_LOCAL_PATH='true'
      ;;
    -u|--skip-extract-used-strings*)
      shift
      SKIP_EXTRACT_USED_STRINGS='true'
      ;;
    -t|--skip-download-translations*)
      shift
      SKIP_DOWNLOAD_TRANSLATIONS='true'
      ;;
    -l|--skip-localization-strings-files*)
      shift
      SKIP_LOCALIZATION_STRINGS_FILES='true'
      ;;
    -d|--debug*)
      shift
      DEBUG='true'
      ;;
    *)
      break
      ;;
  esac
done

# Functions
function join_by { local IFS="$1"; shift; echo "$*"; }

function error() {
  echo -e "\033[0;31m$1\033[0m"
  exit 1
}

function setup_wp_cli() {
  # Install WP-CLI command
  if [[ ! -f "bin/wp-cli.phar" ]]; then
    echo -e "\n\033[1mInstalling WP-CLI\033[0m"
    curl -Ls https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o bin/wp-cli.phar
    chmod +x bin/wp-cli.phar
  fi

  # Upgrading WP-CLI command
  if [[ -z $SKIP_UPGRADE_WP_CLI ]]; then
    echo -e "\n\033[1mUpgrading WP-CLI\033[0m"
    $WP_CLI cli update --nightly --yes
    $WP_CLI --info
  fi
}

function build_gutenberg() {
  if [[ -z $SKIP_GUTENGERG_BUILD ]]; then
    echo -e "\n\033[1mBuild Gutenberg packages\033[0m"
    npm run build:gutenberg
  fi  
}

function generate_bundles() {
  echo -e "\n\033[1mGenerate Android JS bundle\033[0m"
  mkdir -p $JS_BUNDLE_ANDROID_DIR
  npm run rn-bundle -- --platform android --dev false --entry-file $JS_BUNDLE_ENTRY_PATH --bundle-output $JS_BUNDLE_ANDROID_PATH
  
  echo -e "\n\033[1mGenerate iOS JS bundle\033[0m"
  mkdir -p $JS_BUNDLE_IOS_DIR
  npm run rn-bundle -- --platform ios --dev false --entry-file $JS_BUNDLE_ENTRY_PATH --bundle-output $JS_BUNDLE_IOS_PATH
}

function generate_pot_files() {
  local PLUGIN_NAME=$1
  local SOURCE_DIR=$2
  shift 2
  local PLUGINS_TO_SUBTRACT=( $@ )
  local SUBTRACT_POT_FILES=$(join_by , "${@/%/-used.pot}")
  
  local OUTPUT_POT_BLOCKS_FILE="$POT_FILES_DIR/$PLUGIN_NAME-blocks.pot"
  local OUTPUT_POT_USED_ANDROID_FILE="$POT_FILES_DIR/$PLUGIN_NAME-used-android.pot"
  local OUTPUT_POT_USED_IOS_FILE="$POT_FILES_DIR/$PLUGIN_NAME-used-ios.pot"
  local OUTPUT_POT_SOURCE_FILE="$POT_FILES_DIR/$PLUGIN_NAME-source.pot"
  local OUTPUT_POT_SOURCE_ANDROID_FILE="$POT_FILES_DIR/$PLUGIN_NAME-source-android.pot"
  local OUTPUT_POT_SOURCE_IOS_FILE="$POT_FILES_DIR/$PLUGIN_NAME-source-ios.pot"

  local EXCLUDE_FILES="test/*,e2e-tests/*,build/*,build-module/*,build-style/*"

  local DEBUG_PARAM=$([ -z $DEBUG ] && echo "" || echo "--debug")
  local SUBTRACT_PARAM=$([ -z $SUBTRACT_POT_FILES ] && echo "" || echo "--subtract=$SUBTRACT_POT_FILES")
  local DOMAIN_PARAM=$([ "$PLUGIN_NAME" == "gutenberg" ] && echo "--ignore-domain" || echo "--domain=$PLUGIN_NAME")

  echo -e "\n\033[1mExtract strings and generate POT files for \"$PLUGIN_NAME\" plugin from \"$SOURCE_DIR\"\033[0m"

  mkdir -p $POT_FILES_DIR

  if [[ -z $SKIP_EXTRACT_USED_STRINGS ]]; then
    if [ -n "$SUBTRACT_POT_FILES" ]; then
      echo "--- Strings from ${PLUGINS_TO_SUBTRACT[@]} plugins will be subtracted ---"
    fi

    echo -e "\nExtract strings from block JSON files:"
    $WP_CLI i18n make-pot $SOURCE_DIR $DEBUG_PARAM --exclude="$EXCLUDE_FILES" --skip-js --skip-php --ignore-domain $OUTPUT_POT_BLOCKS_FILE
    
    echo -e "\nExtract used strings from Android JS bundle:"
    $WP_CLI i18n make-pot $JS_BUNDLE_ANDROID_DIR $DEBUG_PARAM --include="$JS_BUNDLE_ANDROID_FILENAME" --merge="$OUTPUT_POT_BLOCKS_FILE" $SUBTRACT_PARAM $DOMAIN_PARAM $OUTPUT_POT_USED_ANDROID_FILE

    echo -e "\nExtract used strings from iOS JS bundle:"
    $WP_CLI i18n make-pot $JS_BUNDLE_IOS_DIR $DEBUG_PARAM --include="$JS_BUNDLE_IOS_FILENAME" --merge="$OUTPUT_POT_BLOCKS_FILE" $SUBTRACT_PARAM $DOMAIN_PARAM $OUTPUT_POT_USED_IOS_FILE
  fi

  if [[ -z $SKIP_LOCALIZATION_STRINGS_FILES ]]; then
    # This POT file is only required for generating the localization strings files
    echo -e "\nExtract strings from non-native JS code:"
    EXCLUDE_FILES_WITH_NATIVE="$EXCLUDE_FILES,*.native.js,*.ios.js,*.android.js,bundle/*"
    $WP_CLI i18n make-pot $SOURCE_DIR $DEBUG_PARAM --exclude="$EXCLUDE_FILES_WITH_NATIVE" --merge="$OUTPUT_POT_BLOCKS_FILE" --skip-php $DOMAIN_PARAM $OUTPUT_POT_SOURCE_FILE

    echo -e "\nExtract strings from Android-specific JS code:"
    $WP_CLI i18n make-pot $SOURCE_DIR $DEBUG_PARAM --exclude="$EXCLUDE_FILES" --include="*.native.js,*.android.js" --skip-php --subtract="$OUTPUT_POT_SOURCE_FILE" $DOMAIN_PARAM $OUTPUT_POT_SOURCE_ANDROID_FILE

    echo -e "\nExtract strings from iOS-specific JS code:"
    $WP_CLI i18n make-pot $SOURCE_DIR $DEBUG_PARAM --exclude="$EXCLUDE_FILES" --include="*.native.js,*.ios.js" --skip-php --subtract="$OUTPUT_POT_SOURCE_FILE" $DOMAIN_PARAM $OUTPUT_POT_SOURCE_IOS_FILE
  fi
}

function fetch_translations() {
  local PLUGIN_NAME=$1
  if [[ -z $SKIP_EXTRACT_USED_STRINGS ]]; then
    local ANDROID_POT_FILE="$POT_FILES_DIR/${PLUGIN_NAME/%/-used-android.pot}"
    local IOS_POT_FILE="$POT_FILES_DIR/${PLUGIN_NAME/%/-used-ios.pot}"
  fi

  echo -e "\n\033[1mDownload I18n translations for \"$PLUGIN_NAME\" plugin\033[0m"
  node src/i18n-cache/index.js $PLUGIN_NAME $ANDROID_POT_FILE $IOS_POT_FILE

  if [[ "$PLUGIN_NAME" == "gutenberg" ]]; then
    echo "Update \"react-native-editor\" package i18n cache"
    cp -r src/i18n-cache/gutenberg/data gutenberg/packages/react-native-editor/i18n-cache
    cp src/i18n-cache/gutenberg/index.native.js gutenberg/packages/react-native-editor/i18n-cache
  fi
}

# Get parameters
PLUGINS=( "$@" )

echo -e "\n\033[1m== Updating i18n localizations ==\033[0m"

# Validate parameters
if [[ $((${#PLUGINS[@]}%2)) -ne 0 ]]; then
  error "Plugin arguments must be be even."
fi

for (( index=0; index<${#PLUGINS[@]}; index+=2 )); do
  PLUGIN_FOLDER=${PLUGINS[index+1]}

  if [[ ! -d $PLUGIN_FOLDER ]]; then
    NOT_FOUND_PLUGIN_FOLDERS+=( $PLUGIN_FOLDER )
    echo -e "\033[0;31mPlugin folder \"$PLUGIN_FOLDER\" doesn't exist.\033[0m"
  fi
done
if [[ -n $NOT_FOUND_PLUGIN_FOLDERS ]]; then
  exit 1
fi

# Define constants
WP_CLI="php -d memory_limit=4G bin/wp-cli.phar"
TEMP_DIR=$(mktemp -d)
JS_BUNDLE_ENTRY_PATH="./index.js"

# Set JS bundle directory
if [[ "$USE_LOCAL_PATH" == "true" ]]; then
  JS_BUNDLE_DIR="./bundle"
else
  JS_BUNDLE_DIR="$TEMP_DIR/bundle"
fi

# Set POT files directory
if [[ "$USE_LOCAL_PATH" == "true" ]]; then
  POT_FILES_DIR="./pot"
else
  POT_FILES_DIR="$TEMP_DIR/pot"
fi

# Define JS bundle paths
JS_BUNDLE_ANDROID_DIR="$JS_BUNDLE_DIR/android"
JS_BUNDLE_ANDROID_FILENAME="App.text.js"
JS_BUNDLE_ANDROID_PATH="$JS_BUNDLE_ANDROID_DIR/$JS_BUNDLE_ANDROID_FILENAME"
JS_BUNDLE_IOS_DIR="$JS_BUNDLE_DIR/ios"
JS_BUNDLE_IOS_FILENAME="App.js"
JS_BUNDLE_IOS_PATH="$JS_BUNDLE_IOS_DIR/$JS_BUNDLE_IOS_FILENAME"
JS_BUNDLE_FILES="$JS_BUNDLE_ANDROID,$JS_BUNDLE_IOS"

setup_wp_cli

# Generate JS bundle
if [[ "$USE_LOCAL_PATH" == "true" ]] && ([[ ! -f "$JS_BUNDLE_ANDROID_PATH" ]] || [[ ! -f "$JS_BUNDLE_IOS_PATH" ]]); then
  echo "--- Generating local bundles ---"

  # Build local bundles if don't exist
  build_gutenberg
  npm run bundle
fi

if [[ -z $USE_LOCAL_PATH ]]; then
  build_gutenberg
  generate_bundles
fi

# Generate POT files for plugins (i.e. Jetpack)
for (( index=0; index<${#PLUGINS[@]}; index+=2 )); do
  PLUGIN_NAME=${PLUGINS[index]}
  PLUGIN_FOLDER=${PLUGINS[index+1]}

  PLUGINS_TO_EXTRACT_FROM_GUTENGERG+=( $PLUGIN_NAME )

  generate_pot_files $PLUGIN_NAME $PLUGIN_FOLDER
done

# Generate POT files for Gutenberg
generate_pot_files "gutenberg" "./gutenberg/packages" "${PLUGINS_TO_EXTRACT_FROM_GUTENGERG[@]}"

# Download and optimize translations
if [[ -z $SKIP_DOWNLOAD_TRANSLATIONS ]]; then
  # Download translations of plugins (i.e. Jetpack)
  for (( index=0; index<${#PLUGINS[@]}; index+=2 )); do
    PLUGIN_NAME=${PLUGINS[index]}

    fetch_translations $PLUGIN_NAME
  done

  # Download translations of Gutenberg
  fetch_translations "gutenberg"
fi

if [[ -z $SKIP_LOCALIZATION_STRINGS_FILES ]]; then
  echo -e "\n\033[1mGenerating localization strings files\033[0m"

  # Get POT files for each plugin
  POT_SOURCE_ANDROID_FILES=( "$POT_FILES_DIR/gutenberg-source-android.pot" )
  POT_SOURCE_IOS_FILES=( "$POT_FILES_DIR/gutenberg-source-ios.pot" )
  for (( index=0; index<${#PLUGINS[@]}; index+=2 )); do
    PLUGIN_NAME=${PLUGINS[index]}

    POT_SOURCE_ANDROID_FILES+=( "$POT_FILES_DIR/$PLUGIN_NAME-source-android.pot" )
    POT_SOURCE_IOS_FILES+=( "$POT_FILES_DIR/$PLUGIN_NAME-source-ios.pot" )
  done

  ./bin/po2android.js bundle/android/strings.xml "${POT_SOURCE_ANDROID_FILES[@]}"
  ./bin/po2swift.js bundle/ios/GutenbergNativeTranslations.swift "${POT_SOURCE_IOS_FILES[@]}"
fi
