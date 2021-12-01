#!/bin/bash

# Exit if any command fails
set -e

# Get arguments
while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo "options:"
      echo "-h, --help                          show brief help"
      echo "-p, --skip-pot-files                skip pot files generation"
      echo "-b, --force-bundle                  force JS bundle generation"
      echo "-g, --skip-gutenberg-build          skip Gutenberg build"
      echo "-w, --skip-upgrade-wp-cli           skip WP-CLI upgrade"
      echo "-t, --skip-download-translations    skip translation download"
      exit 0
      ;;
    -p|--skip-pot-files*)
      shift
      SKIP_POT_FILES='true'
      ;;
    -b|--force-bundle*)
      shift
      FORCE_BUNDLE='true'
      ;;
    -g|--skip-gutenberg-build*)
      shift
      SKIP_GUTENGERG_BUILD='true'
      ;;
    -w|--skip-upgrade-wp-cli*)
      shift
      SKIP_UPGRADE_WP_CLI='true'
      ;;
    -t|--skip-download-translations*)
      shift
      SKIP_DOWNLOAD_TRANSLATIONS='true'
      ;;
    *)
      break
      ;;
  esac
done

# Functions
function join_by { local IFS="$1"; shift; echo "$*"; }

function generate_pot_files() {
  local PLUGIN_NAME=$1
  local SOURCE_DIR=$2
  shift 2
  local PLUGINS_TO_SUBTRACT=( $@ )
  local SUBTRACT_POT_FILES=$(join_by , "${@/%/-used.pot}")
  local IGNORE_DOMAIN=$([[ "${PLUGIN_NAME}" == "gutenberg" ]])

  echo -e "\n\033[1mExtract strings and generate POT files for \"$PLUGIN_NAME\" plugin from \"$SOURCE_DIR\"\033[0m"

  if [ -n "$SUBTRACT_POT_FILES" ]; then
    echo "--- Strings from ${PLUGINS_TO_SUBTRACT[@]} plugins will be subtracted ---"
  fi

  echo -e "\nExtract block JSON strings:"
  $WP_CLI i18n make-pot $SOURCE_DIR --skip-js --skip-php --ignore-domain $PLUGIN_NAME-blocks.pot

  local SUBTRACT_PARAM=$([ -z $SUBTRACT_POT_FILES ] && echo "" || echo "--subtract=$SUBTRACT_POT_FILES")
  local DOMAIN_PARAM=$([ "$PLUGIN_NAME" == "gutenberg" ] && echo "--ignore-domain" || echo "--domain=$PLUGIN_NAME")
  echo -e "\nExtract used strings:"
  $WP_CLI i18n make-pot $JS_BUNDLE_DIR --include="$JS_BUNDLE_FILES" --merge="$PLUGIN_NAME-blocks.pot" $SUBTRACT_PARAM $DOMAIN_PARAM $PLUGIN_NAME-used.pot
}

function fetch_translations() {
  local PLUGIN_NAME=$1
  local POT_FILE="${PLUGIN_NAME/%/-used.pot}"

  echo -e "\n\033[1mDownload I18n translations for \"$PLUGIN_NAME\" plugin\033[0m"
  node src/i18n-cache/index.js $PLUGIN_NAME $POT_FILE

  if [[ "$PLUGIN_NAME" == "gutenberg" ]]; then
    echo "Update \"react-native-editor\" package i18n cache"
    cp -r src/i18n-cache/gutenberg/data gutenberg/packages/react-native-editor/i18n-cache
    cp src/i18n-cache/gutenberg/index.native.js gutenberg/packages/react-native-editor/i18n-cache
  fi
}

# Define constants
WP_CLI="php -d memory_limit=4G bin/wp-cli.phar"
JS_BUNDLE_DIR="./bundle"
JS_BUNDLE_ANDROID="android/App.text.js"
JS_BUNDLE_IOS="ios/App.js"
JS_BUNDLE_FILES="$JS_BUNDLE_ANDROID,$JS_BUNDLE_IOS"

PLUGINS=( "$@" )

if [[ $((${#PLUGINS[@]}%2)) -ne 0 ]]; then
  echo "Plugin arguments must be be even."
  exit 1
fi

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

if [[ -ne $FORCE_BUNDLE ]] || ([[ ! -f "$JS_BUNDLE_DIR/$JS_BUNDLE_ANDROID" ]] || [[ ! -f "$JS_BUNDLE_DIR/$JS_BUNDLE_IOS" ]]); then
  # Setup Gutenberg
  if [[ -z $SKIP_GUTENGERG_BUILD ]]; then
    npm run clean:gutenberg && npm run build:gutenberg
  fi  

  npm run bundle
fi

# Generate POT files
if [[ -z $SKIP_POT_FILES ]]; then
  # Generate POT files for plugins (i.e. Jetpack)
  for (( index=0; index<${#PLUGINS[@]}; index+=2 )); do
    PLUGIN_NAME=${PLUGINS[index]}
    PLUGIN_FOLDER=${PLUGINS[index+1]}

    PLUGINS_TO_EXTRACT_FROM_GUTENGERG+=( $PLUGIN_NAME )

    generate_pot_files $PLUGIN_NAME $PLUGIN_FOLDER
  done
  
  # Generate POT files for Gutenberg
  generate_pot_files "gutenberg" "./gutenberg/packages" "${PLUGINS_TO_EXTRACT_FROM_GUTENGERG[@]}"
fi

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