#!/bin/bash
#
# ios-ui-test.sh - Manual E2E UI test suite for VoiceLog iOS app
#
# Uses IDB (Instagram Debug Bridge) for UI automation testing.
# Requires: idb, jq, running backend, booted simulator with app installed
#
# Usage:
#   ./scripts/ios-ui-test.sh all              # Run all tests
#   ./scripts/ios-ui-test.sh login            # Run single test
#   ./scripts/ios-ui-test.sh --list           # List available tests
#   ./scripts/ios-ui-test.sh --help           # Show help
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

# Test user credentials
TEST_EMAIL="testuser_$(date +%s)@voicelog.com"
TEST_PASSWORD="testpassword123"
TEST_NAME="Test User"

# Existing dev credentials (for login tests)
DEV_EMAIL="dev@voicelog.com"
DEV_PASSWORD="devpassword123"

# iOS configuration
SIMULATOR_NAME="iPhone 17 Pro"
APP_BUNDLE_ID="com.voicelog.VoiceLogApp"

# Test timing
ELEMENT_TIMEOUT=10
TAP_DELAY=0.5
TYPE_DELAY=0.1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

# Get simulator UDID
get_simulator_udid() {
    xcrun simctl list devices available -j | jq -r ".devices | to_entries[] | .value[] | select(.name == \"${SIMULATOR_NAME}\" and .state == \"Booted\") | .udid" | head -1
}

# ============================================================================
# IDB Wrapper Functions
# ============================================================================

# Wait for an element to appear
wait_for_element() {
    local identifier=$1
    local timeout=${2:-$ELEMENT_TIMEOUT}

    for ((i=0; i<timeout; i++)); do
        if idb ui describe-all --udid "$UDID" 2>/dev/null | jq -e ".[] | select(.AXUniqueId == \"$identifier\")" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Check if element exists (no waiting)
element_exists() {
    local identifier=$1
    idb ui describe-all --udid "$UDID" 2>/dev/null | jq -e ".[] | select(.AXUniqueId == \"$identifier\")" > /dev/null 2>&1
}

# Get element info
get_element() {
    local identifier=$1
    idb ui describe-all --udid "$UDID" 2>/dev/null | jq ".[] | select(.AXUniqueId == \"$identifier\")"
}

# Tap an element by accessibility identifier
tap_element() {
    local identifier=$1

    log_info "Tapping '$identifier'..."

    if ! wait_for_element "$identifier"; then
        log_error "Element '$identifier' not found"
        return 1
    fi

    # Get element frame
    local element=$(get_element "$identifier")
    local frame=$(echo "$element" | jq -r '.frame')
    local x=$(echo "$frame" | jq -r '(.x + (.width / 2)) | floor')
    local y=$(echo "$frame" | jq -r '(.y + (.height / 2)) | floor')

    idb ui tap --udid "$UDID" "$x" "$y"
    sleep "$TAP_DELAY"
}

# Type text into the focused field
type_text() {
    local text=$1

    log_info "Typing text..."
    idb ui text --udid "$UDID" "$text"
    sleep "$TYPE_DELAY"
}

# Clear text field and type new text
clear_and_type() {
    local identifier=$1
    local text=$2

    tap_element "$identifier"

    # Select all and delete (triple tap to select all on iOS)
    local element=$(get_element "$identifier")
    local frame=$(echo "$element" | jq -r '.frame')
    local x=$(echo "$frame" | jq -r '(.x + (.width / 2)) | floor')
    local y=$(echo "$frame" | jq -r '(.y + (.height / 2)) | floor')

    # Triple tap to select all
    idb ui tap --udid "$UDID" "$x" "$y"
    sleep 0.1
    idb ui tap --udid "$UDID" "$x" "$y"
    sleep 0.1
    idb ui tap --udid "$UDID" "$x" "$y"
    sleep 0.2

    # Type new text (replaces selection)
    type_text "$text"
}

# Press hardware button
press_button() {
    local button=$1
    idb ui button --udid "$UDID" "$button"
    sleep "$TAP_DELAY"
}

# Take screenshot
take_screenshot() {
    local name=$1
    local path="${PROJECT_ROOT}/test-screenshots/${name}.png"
    mkdir -p "$(dirname "$path")"
    idb screenshot --udid "$UDID" "$path"
    log_info "Screenshot saved: $path"
}

# ============================================================================
# Assertion Functions
# ============================================================================

assert_element_exists() {
    local identifier=$1
    local message=${2:-"Element '$identifier' should exist"}

    if wait_for_element "$identifier"; then
        log_success "$message"
        return 0
    else
        log_error "$message"
        take_screenshot "assert_fail_$(date +%s)"
        return 1
    fi
}

assert_element_not_exists() {
    local identifier=$1
    local message=${2:-"Element '$identifier' should not exist"}

    sleep 1  # Brief wait to ensure UI has settled
    if ! element_exists "$identifier"; then
        log_success "$message"
        return 0
    else
        log_error "$message"
        take_screenshot "assert_fail_$(date +%s)"
        return 1
    fi
}

assert_element_contains_text() {
    local identifier=$1
    local expected_text=$2
    local message=${3:-"Element '$identifier' should contain '$expected_text'"}

    if ! wait_for_element "$identifier"; then
        log_error "Element '$identifier' not found"
        return 1
    fi

    local element=$(get_element "$identifier")
    local label=$(echo "$element" | jq -r '.label // .value // ""')

    if [[ "$label" == *"$expected_text"* ]]; then
        log_success "$message"
        return 0
    else
        log_error "$message (got: '$label')"
        take_screenshot "assert_fail_$(date +%s)"
        return 1
    fi
}

# ============================================================================
# Backend Helper Functions
# ============================================================================

# Create a test user via API
create_test_user() {
    local email=$1
    local password=$2
    local name=$3

    local response=$(curl -s -X POST "${BACKEND_URL}/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${name}\", \"email\": \"${email}\", \"password\": \"${password}\"}")

    if echo "$response" | jq -e '.access_token' > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Delete test user (cleanup)
delete_test_user() {
    local email=$1
    # Note: Would need admin API or direct DB access for cleanup
    # For now, just log
    log_info "Test user cleanup: $email (manual cleanup may be needed)"
}

# Check if backend is running
check_backend() {
    if ! curl -s "${BACKEND_URL}/" > /dev/null 2>&1; then
        log_error "Backend not running at ${BACKEND_URL}"
        echo "Start the backend with: ./scripts/local-dev.sh"
        exit 1
    fi
}

# ============================================================================
# App Control Functions
# ============================================================================

launch_app() {
    log_info "Launching app..."
    xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" 2>/dev/null || true
    sleep 0.5
    xcrun simctl launch "$UDID" "$APP_BUNDLE_ID"
    sleep 2  # Wait for app to fully launch
}

terminate_app() {
    log_info "Terminating app..."
    xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" 2>/dev/null || true
    sleep 0.5
}

reset_app_state() {
    log_info "Resetting app state..."
    terminate_app
    # Remove app data
    xcrun simctl uninstall "$UDID" "$APP_BUNDLE_ID" 2>/dev/null || true

    # Reinstall app
    local app_path=$(find "${PROJECT_ROOT}/VoiceLogApp/build" -name "*.app" -type d | head -1)
    if [ -n "$app_path" ]; then
        xcrun simctl install "$UDID" "$app_path"
    else
        log_error "App not found. Run ./scripts/local-dev.sh first."
        exit 1
    fi
}

# ============================================================================
# Test Functions
# ============================================================================

test_login_flow() {
    log_test "Login Flow - Valid credentials"

    launch_app

    # Verify login screen elements exist
    assert_element_exists "login_email_field" "Email field exists"
    assert_element_exists "login_password_field" "Password field exists"
    assert_element_exists "login_submit_button" "Submit button exists"

    # Enter credentials
    clear_and_type "login_email_field" "$DEV_EMAIL"
    clear_and_type "login_password_field" "$DEV_PASSWORD"

    # Tap login
    tap_element "login_submit_button"

    # Should navigate to notes list
    assert_element_exists "notes_tab" "Successfully logged in - notes tab visible"

    terminate_app
}

test_login_invalid_credentials() {
    log_test "Login Flow - Invalid credentials"

    reset_app_state
    launch_app

    # Verify login elements exist
    assert_element_exists "login_email_field" "Login email field is displayed"

    # Enter invalid credentials
    clear_and_type "login_email_field" "invalid@example.com"
    clear_and_type "login_password_field" "wrongpassword"

    # Tap login
    tap_element "login_submit_button"

    # Should show error message
    sleep 2  # Wait for API response
    assert_element_exists "login_error_message" "Error message is displayed for invalid credentials"

    # Should still be on login screen (email field still visible)
    assert_element_exists "login_email_field" "Still on login screen after failed login"

    terminate_app
}

test_register_flow() {
    log_test "Registration Flow"

    local unique_email="test_$(date +%s)@voicelog.com"

    reset_app_state
    launch_app

    # Tap sign up link
    assert_element_exists "signup_link" "Sign up link exists"
    tap_element "signup_link"

    # Verify register form fields exist
    sleep 1
    assert_element_exists "register_name_field" "Name field exists"
    assert_element_exists "register_email_field" "Email field exists"
    assert_element_exists "register_password_field" "Password field exists"
    assert_element_exists "register_confirm_password_field" "Confirm password field exists"

    # Fill in registration form
    clear_and_type "register_name_field" "Test User"
    clear_and_type "register_email_field" "$unique_email"
    clear_and_type "register_password_field" "testpassword123"
    clear_and_type "register_confirm_password_field" "testpassword123"

    # Submit registration
    tap_element "register_submit_button"

    # Should navigate to notes list after successful registration
    assert_element_exists "notes_tab" "Successfully registered - notes tab visible"

    terminate_app
}

test_logout_flow() {
    log_test "Logout Flow"

    launch_app

    # Login first if needed
    if element_exists "login_email_field"; then
        clear_and_type "login_email_field" "$DEV_EMAIL"
        clear_and_type "login_password_field" "$DEV_PASSWORD"
        tap_element "login_submit_button"
        sleep 2
    fi

    # Navigate to settings
    assert_element_exists "settings_tab" "Settings tab exists"
    tap_element "settings_tab"

    # Verify settings elements
    sleep 1
    assert_element_exists "signout_button" "Sign out button exists"

    # Tap sign out
    tap_element "signout_button"

    # Confirm sign out
    sleep 1
    assert_element_exists "signout_confirm_button" "Sign out confirmation dialog shown"
    tap_element "signout_confirm_button"

    # Should be back on login screen (email field visible)
    sleep 1
    assert_element_exists "login_email_field" "Back on login screen after logout"

    terminate_app
}

test_notes_list() {
    log_test "Notes List View"

    launch_app

    # Login if needed
    if element_exists "login_email_field"; then
        clear_and_type "login_email_field" "$DEV_EMAIL"
        clear_and_type "login_password_field" "$DEV_PASSWORD"
        tap_element "login_submit_button"
        sleep 2
    fi

    # Should be on notes tab
    assert_element_exists "notes_tab" "Notes tab is visible"
    tap_element "notes_tab"

    # Check for notes list or empty state
    sleep 2
    if element_exists "notes_list"; then
        log_success "Notes list is displayed"
    elif element_exists "empty_notes_view"; then
        log_success "Empty notes view is displayed (no notes yet)"
    else
        log_error "Neither notes list nor empty view found"
        return 1
    fi

    # Add note button should exist
    assert_element_exists "add_note_button" "Add note button exists"

    terminate_app
}

test_note_detail() {
    log_test "Note Detail View"

    launch_app

    # Login if needed
    if element_exists "login_email_field"; then
        clear_and_type "login_email_field" "$DEV_EMAIL"
        clear_and_type "login_password_field" "$DEV_PASSWORD"
        tap_element "login_submit_button"
        sleep 2
    fi

    # Navigate to notes
    tap_element "notes_tab"
    sleep 2

    # Check if there are any notes
    if element_exists "empty_notes_view"; then
        log_warn "No notes available - skipping note detail test"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        terminate_app
        return 0
    fi

    # Get first note and tap it
    # Find any element with "note_row_" prefix
    local notes_ui=$(idb ui describe-all --udid "$UDID" 2>/dev/null)
    local first_note=$(echo "$notes_ui" | jq -r '[.[] | select(.AXUniqueId | tostring | startswith("note_row_"))] | .[0].AXUniqueId // empty')

    if [ -n "$first_note" ]; then
        tap_element "$first_note"

        # Verify note detail elements
        sleep 1
        assert_element_exists "note_detail_transcript" "Transcript is displayed"

        # Go back
        press_button "HOME"
    else
        log_warn "No notes found in list"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi

    terminate_app
}

test_create_note_ui() {
    log_test "Create Note UI (without actual recording)"

    launch_app

    # Login if needed
    if element_exists "login_email_field"; then
        clear_and_type "login_email_field" "$DEV_EMAIL"
        clear_and_type "login_password_field" "$DEV_PASSWORD"
        tap_element "login_submit_button"
        sleep 2
    fi

    # Navigate to notes
    tap_element "notes_tab"
    sleep 1

    # Tap add note button
    assert_element_exists "add_note_button" "Add note button exists"
    tap_element "add_note_button"

    # Verify recording screen elements
    sleep 1
    assert_element_exists "record_button" "Record button exists"
    assert_element_exists "recording_cancel_button" "Cancel button exists in toolbar"

    # Note: We cannot test actual recording in simulator (no microphone)
    log_warn "Actual recording cannot be tested in simulator (no microphone access)"

    # Cancel and go back
    tap_element "recording_cancel_button"

    # Should be back on notes list
    sleep 1
    assert_element_exists "notes_tab" "Back on notes list"

    terminate_app
}

test_empty_notes_state() {
    log_test "Empty Notes State"

    reset_app_state
    launch_app

    # Register a new user so we have no notes
    local unique_email="empty_test_$(date +%s)@voicelog.com"

    tap_element "signup_link"
    sleep 1

    clear_and_type "register_name_field" "Empty Test"
    clear_and_type "register_email_field" "$unique_email"
    clear_and_type "register_password_field" "testpassword123"
    clear_and_type "register_confirm_password_field" "testpassword123"

    tap_element "register_submit_button"
    sleep 2

    # Should show empty notes view
    assert_element_exists "empty_notes_view" "Empty notes view is displayed for new user"

    terminate_app
}

test_settings_screen() {
    log_test "Settings Screen"

    launch_app

    # Login if needed
    if element_exists "login_email_field"; then
        clear_and_type "login_email_field" "$DEV_EMAIL"
        clear_and_type "login_password_field" "$DEV_PASSWORD"
        tap_element "login_submit_button"
        sleep 2
    fi

    # Navigate to settings
    tap_element "settings_tab"
    sleep 1

    # Check settings elements
    assert_element_exists "settings_user_name" "User name is displayed"
    assert_element_exists "settings_user_email" "User email is displayed"
    assert_element_exists "sync_now_button" "Sync now button exists"
    assert_element_exists "signout_button" "Sign out button exists"

    terminate_app
}

# ============================================================================
# Test Runner
# ============================================================================

run_test() {
    local test_name=$1
    local test_func="test_${test_name}"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if declare -f "$test_func" > /dev/null; then
        if $test_func; then
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        log_error "Unknown test: $test_name"
        return 1
    fi
}

run_all_tests() {
    local tests=(
        "login_flow"
        "login_invalid_credentials"
        "register_flow"
        "logout_flow"
        "notes_list"
        "note_detail"
        "create_note_ui"
        "empty_notes_state"
        "settings_screen"
    )

    for test in "${tests[@]}"; do
        run_test "$test"
    done
}

list_tests() {
    echo "Available tests:"
    echo ""
    echo "  login_flow              - Login with valid credentials"
    echo "  login_invalid_credentials - Login with wrong password"
    echo "  register_flow           - Full registration flow"
    echo "  logout_flow             - Sign out from settings"
    echo "  notes_list              - View notes list"
    echo "  note_detail             - View note detail"
    echo "  create_note_ui          - Recording UI (no actual audio)"
    echo "  empty_notes_state       - Empty state for new user"
    echo "  settings_screen         - Settings screen elements"
    echo ""
    echo "Usage:"
    echo "  $0 all                  - Run all tests"
    echo "  $0 <test_name>          - Run single test"
    echo "  $0 --list               - List available tests"
}

print_results() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Test Results${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "  ${GREEN}All tests passed!${NC}"
    else
        echo -e "  ${RED}Some tests failed.${NC}"
    fi
    echo ""
}

show_help() {
    echo "ios-ui-test.sh - Manual E2E UI test suite for VoiceLog"
    echo ""
    echo "Usage:"
    echo "  $0 all                  - Run all tests"
    echo "  $0 <test_name>          - Run single test"
    echo "  $0 --list               - List available tests"
    echo "  $0 --help               - Show this help"
    echo ""
    echo "Prerequisites:"
    echo "  - idb (Instagram Debug Bridge): pip install fb-idb"
    echo "  - jq: brew install jq"
    echo "  - Backend running: ./scripts/local-dev.sh"
    echo "  - Simulator booted with app installed"
    echo ""
    echo "Note: Voice recording tests are limited because iOS Simulator"
    echo "cannot capture actual audio. Test test_create_note_ui verifies"
    echo "the UI elements only."
}

cleanup() {
    terminate_app 2>/dev/null || true
}

# ============================================================================
# Main
# ============================================================================

main() {
    trap cleanup EXIT

    # Check dependencies
    if ! command -v idb &> /dev/null; then
        log_error "idb not found. Install with: pip install fb-idb"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install with: brew install jq"
        exit 1
    fi

    # Get simulator UDID
    UDID=$(get_simulator_udid)
    if [ -z "$UDID" ]; then
        log_error "No booted simulator found with name '${SIMULATOR_NAME}'"
        echo "Boot a simulator with: xcrun simctl boot '$SIMULATOR_NAME'"
        exit 1
    fi

    # Check backend
    check_backend

    # Ensure dev user exists
    create_test_user "$DEV_EMAIL" "$DEV_PASSWORD" "Dev User" 2>/dev/null || true

    # Parse arguments
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --list|-l)
            list_tests
            exit 0
            ;;
        all)
            echo ""
            echo -e "${BLUE}VoiceLog iOS UI Test Suite${NC}"
            echo -e "${BLUE}Simulator: ${SIMULATOR_NAME} (${UDID})${NC}"
            run_all_tests
            print_results
            exit $TESTS_FAILED
            ;;
        "")
            show_help
            exit 0
            ;;
        *)
            echo ""
            echo -e "${BLUE}VoiceLog iOS UI Test Suite${NC}"
            echo -e "${BLUE}Simulator: ${SIMULATOR_NAME} (${UDID})${NC}"
            run_test "$1"
            print_results
            exit $TESTS_FAILED
            ;;
    esac
}

main "$@"
