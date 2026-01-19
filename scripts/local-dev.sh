#!/bin/bash
#
# local-dev.sh - Quick local development setup for VoiceLog
#
# This script:
# 1. Starts the backend server with dev environment
# 2. Creates a dev user account via API
# 3. Boots iOS simulator
# 4. Builds and installs the app
# 5. Launches the app ready for manual testing
# 6. Prints dev credentials for easy login
#
# Usage: ./scripts/local-dev.sh
#

set -e

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Backend configuration
BACKEND_PORT=8000
BACKEND_URL="http://localhost:${BACKEND_PORT}"
DEV_JWT_SECRET="dev-secret-key-for-local-testing-only"

# Dev user credentials
DEV_EMAIL="dev@voicelog.com"
DEV_PASSWORD="devpassword123"
DEV_NAME="Dev User"

# iOS configuration
SIMULATOR_NAME="iPhone 17 Pro"
APP_BUNDLE_ID="com.voicelog.VoiceLogApp"
XCODE_PROJECT="${PROJECT_ROOT}/VoiceLogApp/VoiceLogApp.xcodeproj"
XCODE_SCHEME="VoiceLogApp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    local missing=()

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v xcrun &> /dev/null; then
        missing+=("xcrun (Xcode)")
    fi

    if ! command -v idb &> /dev/null; then
        missing+=("idb (pip install fb-idb)")
    fi

    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Please install the missing dependencies and try again."
        exit 1
    fi
}

# ============================================================================
# Backend Functions
# ============================================================================

start_backend() {
    log_info "Starting backend server..."

    # Check if backend is already running
    if curl -s "${BACKEND_URL}/health" > /dev/null 2>&1; then
        log_warn "Backend already running on port ${BACKEND_PORT}"
        return 0
    fi

    cd "${PROJECT_ROOT}"

    # Start backend in background with dev settings
    JWT_SECRET="${DEV_JWT_SECRET}" \
    DATABASE_URL="sqlite:///./dev.db" \
    OPENAI_API_KEY="${OPENAI_API_KEY:-dummy-key-for-dev}" \
    python3 -m uvicorn app.main:app --host 0.0.0.0 --port "${BACKEND_PORT}" &

    BACKEND_PID=$!
    echo $BACKEND_PID > /tmp/voicelog-backend.pid

    # Wait for backend to start
    log_info "Waiting for backend to start..."
    for i in {1..30}; do
        if curl -s "${BACKEND_URL}/health" > /dev/null 2>&1; then
            log_success "Backend started (PID: ${BACKEND_PID})"
            return 0
        fi
        sleep 1
    done

    log_error "Backend failed to start"
    exit 1
}

stop_backend() {
    if [ -f /tmp/voicelog-backend.pid ]; then
        local pid=$(cat /tmp/voicelog-backend.pid)
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping backend (PID: ${pid})..."
            kill "$pid"
            rm /tmp/voicelog-backend.pid
        fi
    fi
}

setup_dev_user() {
    log_info "Setting up dev user account..."

    # Check if user already exists by trying to login
    local login_response=$(curl -s -X POST "${BACKEND_URL}/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"${DEV_EMAIL}\", \"password\": \"${DEV_PASSWORD}\"}")

    if echo "$login_response" | jq -e '.access_token' > /dev/null 2>&1; then
        log_success "Dev user already exists"
        return 0
    fi

    # Register new user
    local register_response=$(curl -s -X POST "${BACKEND_URL}/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${DEV_NAME}\", \"email\": \"${DEV_EMAIL}\", \"password\": \"${DEV_PASSWORD}\"}")

    if echo "$register_response" | jq -e '.access_token' > /dev/null 2>&1; then
        log_success "Dev user created"
    else
        local error=$(echo "$register_response" | jq -r '.detail // "Unknown error"')
        log_error "Failed to create dev user: ${error}"
        exit 1
    fi
}

# ============================================================================
# iOS Simulator Functions
# ============================================================================

boot_simulator() {
    log_info "Booting iOS simulator..."

    # Get simulator UDID
    local udid=$(xcrun simctl list devices available -j | jq -r ".devices | to_entries[] | .value[] | select(.name == \"${SIMULATOR_NAME}\") | .udid" | head -1)

    if [ -z "$udid" ]; then
        log_error "Simulator '${SIMULATOR_NAME}' not found"
        echo "Available simulators:"
        xcrun simctl list devices available | grep -E "iPhone|iPad"
        exit 1
    fi

    # Check if already booted
    local state=$(xcrun simctl list devices -j | jq -r ".devices | to_entries[] | .value[] | select(.udid == \"${udid}\") | .state")

    if [ "$state" == "Booted" ]; then
        log_success "Simulator already booted"
    else
        xcrun simctl boot "$udid"
        log_success "Simulator booted"
    fi

    # Open Simulator app
    open -a Simulator

    # Wait for simulator to be ready
    sleep 2

    echo "$udid"
}

# ============================================================================
# App Build Functions
# ============================================================================

generate_xcode_project() {
    log_info "Checking Xcode project..."

    if [ ! -d "$XCODE_PROJECT" ]; then
        log_info "Generating Xcode project with xcodegen..."
        cd "${PROJECT_ROOT}/VoiceLogApp"

        if ! command -v xcodegen &> /dev/null; then
            log_error "xcodegen not found. Install with: brew install xcodegen"
            exit 1
        fi

        xcodegen generate
        log_success "Xcode project generated"
    else
        log_success "Xcode project exists"
    fi
}

build_and_install_app() {
    local udid=$1

    log_info "Building app..."

    cd "${PROJECT_ROOT}/VoiceLogApp"

    # Build for simulator
    xcodebuild \
        -project VoiceLogApp.xcodeproj \
        -scheme "${XCODE_SCHEME}" \
        -sdk iphonesimulator \
        -destination "id=${udid}" \
        -configuration Debug \
        -derivedDataPath build \
        build 2>&1 | xcbeautify || xcodebuild \
        -project VoiceLogApp.xcodeproj \
        -scheme "${XCODE_SCHEME}" \
        -sdk iphonesimulator \
        -destination "id=${udid}" \
        -configuration Debug \
        -derivedDataPath build \
        build

    log_success "App built"

    # Find and install the app
    local app_path=$(find build -name "*.app" -type d | head -1)

    if [ -z "$app_path" ]; then
        log_error "Built app not found"
        exit 1
    fi

    log_info "Installing app..."
    xcrun simctl install "$udid" "$app_path"
    log_success "App installed"
}

launch_app() {
    local udid=$1

    log_info "Launching app..."
    xcrun simctl launch "$udid" "${APP_BUNDLE_ID}"
    log_success "App launched"
}

# ============================================================================
# Main
# ============================================================================

print_credentials() {
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  VoiceLog Dev Environment Ready!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "  Backend URL: ${BLUE}${BACKEND_URL}${NC}"
    echo ""
    echo -e "  ${YELLOW}Dev Login Credentials:${NC}"
    echo -e "  Email:    ${BLUE}${DEV_EMAIL}${NC}"
    echo -e "  Password: ${BLUE}${DEV_PASSWORD}${NC}"
    echo ""
    echo -e "  Press Ctrl+C to stop the backend server."
    echo ""
}

cleanup() {
    echo ""
    log_info "Cleaning up..."
    stop_backend
    log_success "Done"
}

trap cleanup EXIT

main() {
    echo ""
    echo -e "${BLUE}VoiceLog Local Development Setup${NC}"
    echo ""

    check_dependencies

    # Start backend
    start_backend
    setup_dev_user

    # Setup iOS
    generate_xcode_project
    local udid=$(boot_simulator)
    build_and_install_app "$udid"
    launch_app "$udid"

    print_credentials

    # Keep script running to maintain backend
    wait
}

# Run main function
main "$@"
