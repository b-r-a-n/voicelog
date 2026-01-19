# VoiceLog - Outstanding Issues

## Critical: iOS App API Response Decoding Error

**Status:** Blocking E2E tests

**Error Message:**
```
Failed to decode response: The data couldn't be read because it isn't in the correct format.
```

**Description:**
The iOS app cannot parse API responses from the backend for login and registration endpoints. The E2E test infrastructure is working correctly (finds UI elements, types text, taps buttons), but login/registration fails due to response format mismatch.

**Affected Endpoints:**
- `POST /auth/login`
- `POST /auth/register`

**Investigation Needed:**
1. Compare iOS app's expected response models (in `AuthService.swift` or API client) with actual backend responses
2. Check if the backend returns the expected fields (`access_token`, `user`, etc.)
3. Verify JSON field naming conventions match (snake_case vs camelCase)

**Backend Response Example:**
```json
{
  "name": "Dev User",
  "email": "dev@voicelog.com",
  "id": 1,
  "created_at": "2026-01-19T11:41:20",
  "updated_at": "2026-01-19T11:41:20"
}
```

**Likely Fix:**
- Update iOS app's Codable models to match backend response format, OR
- Update backend to return response format expected by iOS app (likely needs `access_token` field)

---

## Minor: SpeechAnalyzer API (iOS 26)

**Status:** Worked around

The codebase contained code for a hypothetical `SpeechAnalyzer` API for iOS 26 which doesn't exist yet. This has been removed and the app now uses only the legacy `SFSpeechRecognizer` strategy which works with current iOS versions.

---

## E2E Test Infrastructure

**Status:** Complete and functional

The IDB-based E2E test scripts are working:
- `scripts/local-dev.sh` - Sets up local dev environment
- `scripts/ios-ui-test.sh` - Runs UI automation tests

Tests will pass once the API response format issue is resolved.

---

## Resolved Issues

### Fixed: Transcript Loss on Session Restart

**Status:** Resolved (2026-01-19)

**Problem:** When dictating for longer than 60 seconds, the speech recognition session would restart (to work around Apple's ~60-second limit), but the previously transcribed text was lost.

**Root Cause:** In `SpeechService.swift`, when `recognitionTask?.cancel()` was called during restart, the old session's callback could still fire asynchronously. If it fired after the new session started, it would overwrite `accumulatedTranscript` using the old `sessionStartTranscript` value.

**Fix:** Added session ID tracking (`currentSessionId`) to ignore callbacks from stale sessions. See commit `7ef8bc9`.
