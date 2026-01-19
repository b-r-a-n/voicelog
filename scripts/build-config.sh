#!/bin/bash
#
# build-config.sh - Centralized build configuration for VoiceLog iOS app
#
# Source this file from other scripts to ensure consistent build paths.
# All scripts should use these paths to avoid build location mismatches.
#
# Usage: source "${SCRIPT_DIR}/build-config.sh"
#

# Determine PROJECT_ROOT if not already set
if [ -z "$PROJECT_ROOT" ]; then
    _BUILD_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$_BUILD_CONFIG_DIR")"
fi

# ============================================================================
# Build Path Configuration
# ============================================================================

# Root directory for all iOS build outputs
export VOICELOG_BUILD_ROOT="${PROJECT_ROOT}/VoiceLogApp/build"

# DerivedData path - all xcodebuild commands should use this
export VOICELOG_DERIVED_DATA="${VOICELOG_BUILD_ROOT}"

# Expected location of the built app bundle
export VOICELOG_APP_PATH="${VOICELOG_BUILD_ROOT}/Build/Products/Debug-iphonesimulator/VoiceLogApp.app"

# ============================================================================
# Build Commands Reference
# ============================================================================
#
# To build the app with correct paths, use:
#
#   cd VoiceLogApp && xcodebuild \
#       -project VoiceLogApp.xcodeproj \
#       -scheme VoiceLogApp \
#       -sdk iphonesimulator \
#       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
#       -configuration Debug \
#       -derivedDataPath ./build \
#       build
#
# Or with a specific simulator UDID:
#
#   cd VoiceLogApp && xcodebuild \
#       -project VoiceLogApp.xcodeproj \
#       -scheme VoiceLogApp \
#       -sdk iphonesimulator \
#       -destination "id=${UDID}" \
#       -configuration Debug \
#       -derivedDataPath ./build \
#       build
#
