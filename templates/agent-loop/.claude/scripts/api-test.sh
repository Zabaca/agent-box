#!/bin/bash
#
# API Test Runner
# Automated testing tool for HTTP APIs with test suite support
#
# Usage: api-test.sh [options] [test-file]
#   -u URL        Base URL for API (default: http://localhost:3000)
#   -t TIMEOUT    Request timeout in seconds (default: 10)
#   -v            Verbose output
#   -q            Quiet mode (only show failures)
#   --json        Output results as JSON
#   --junit       Output results as JUnit XML
#   -h            Show help
#
# Test file format (YAML-like):
#   # Comment
#   TEST: Test name
#   METHOD: GET|POST|PUT|DELETE|PATCH
#   PATH: /api/endpoint
#   HEADERS: Header-Name: value
#   BODY: {"json": "data"}
#   EXPECT_STATUS: 200
#   EXPECT_BODY: substring to match
#   EXPECT_JSON: .path.to.field=expected_value
#   ---

set -uo pipefail

# Defaults
BASE_URL="http://localhost:3000"
TIMEOUT=10
VERBOSE=false
QUIET=false
OUTPUT_FORMAT="text"
TEST_FILE=""

# Results
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TESTS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat << 'EOF'
API Test Runner - Automated HTTP API testing

Usage: api-test.sh [options] [test-file]

Options:
  -u URL        Base URL for API (default: http://localhost:3000)
  -t TIMEOUT    Request timeout in seconds (default: 10)
  -v            Verbose output
  -q            Quiet mode (only show failures)
  --json        Output results as JSON
  --junit       Output results as JUnit XML
  -h, --help    Show this help

Test File Format:
  Create a .api-test file with test definitions:

  # Test health endpoint
  TEST: Health check returns OK
  METHOD: GET
  PATH: /health
  EXPECT_STATUS: 200
  EXPECT_BODY: healthy
  ---

  # Test with JSON body
  TEST: Create user
  METHOD: POST
  PATH: /api/users
  HEADERS: Content-Type: application/json
  HEADERS: Authorization: Bearer token123
  BODY: {"name": "test", "email": "test@example.com"}
  EXPECT_STATUS: 201
  EXPECT_JSON: .id
  EXPECT_JSON: .name=test
  ---

Assertions:
  EXPECT_STATUS: HTTP status code (200, 201, 404, etc.)
  EXPECT_BODY: Response body contains this substring
  EXPECT_JSON: jq expression to validate JSON response
              .field          - field exists
              .field=value    - field equals value
              .field!=value   - field not equals value
              .array|length>0 - array has items

Examples:
  api-test.sh tests/api.test              # Run test file
  api-test.sh -u http://api.local tests/  # Test all files in directory
  api-test.sh -v --json tests/api.test    # Verbose JSON output
EOF
}

log_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${GREEN}✓${NC} $1"
    fi
    TESTS+=("{\"name\":\"$1\",\"status\":\"pass\"}")
}

log_fail() {
    local name="$1"
    local reason="${2:-}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "${RED}✗${NC} $name"
    if [[ -n "$reason" ]]; then
        echo -e "  ${RED}→${NC} $reason"
    fi
    TESTS+=("{\"name\":\"$name\",\"status\":\"fail\",\"reason\":\"$reason\"}")
}

log_skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${YELLOW}○${NC} $1 (skipped)"
    fi
    TESTS+=("{\"name\":\"$1\",\"status\":\"skip\"}")
}

log_info() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}  →${NC} $1"
    fi
}

# Run a single test
run_test() {
    local test_name="$1"
    local method="$2"
    local path="$3"
    local headers="$4"
    local body="$5"
    local expect_status="$6"
    local expect_body="$7"
    local expect_json="$8"

    log_info "Testing: $method $path"

    # Build curl command
    local curl_args=(-s -w "\n%{http_code}" --max-time "$TIMEOUT")

    # Add method
    curl_args+=(-X "$method")

    # Add headers
    if [[ -n "$headers" ]]; then
        while IFS= read -r header; do
            [[ -n "$header" ]] && curl_args+=(-H "$header")
        done <<< "$headers"
    fi

    # Add body
    if [[ -n "$body" ]]; then
        curl_args+=(--data-raw "$body")
    fi

    # Make request
    local url="${BASE_URL}${path}"
    local response
    local http_code

    if ! response=$(curl "${curl_args[@]}" "$url" 2>&1); then
        log_fail "$test_name" "Request failed: curl error"
        return 1
    fi

    # Extract status code (last line)
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    log_info "Status: $http_code"
    if [[ "$VERBOSE" == "true" ]] && [[ -n "$response" ]]; then
        log_info "Response: ${response:0:200}..."
    fi

    # Check status
    if [[ -n "$expect_status" ]]; then
        if [[ "$http_code" != "$expect_status" ]]; then
            log_fail "$test_name" "Expected status $expect_status, got $http_code"
            return 1
        fi
    fi

    # Check body contains substring
    if [[ -n "$expect_body" ]]; then
        if ! echo "$response" | grep -qF "$expect_body"; then
            log_fail "$test_name" "Response body does not contain: $expect_body"
            return 1
        fi
    fi

    # Check JSON assertions
    if [[ -n "$expect_json" ]]; then
        while IFS= read -r assertion; do
            [[ -z "$assertion" ]] && continue

            if [[ "$assertion" == *"="* ]]; then
                # Check field equals value
                local field="${assertion%%=*}"
                local expected="${assertion#*=}"

                # Handle != operator
                if [[ "$field" == *"!" ]]; then
                    field="${field%!}"
                    local actual
                    actual=$(echo "$response" | jq -r "$field" 2>/dev/null)
                    if [[ "$actual" == "$expected" ]]; then
                        log_fail "$test_name" "JSON $field should not equal $expected"
                        return 1
                    fi
                else
                    local actual
                    actual=$(echo "$response" | jq -r "$field" 2>/dev/null)
                    if [[ "$actual" != "$expected" ]]; then
                        log_fail "$test_name" "JSON $field expected '$expected', got '$actual'"
                        return 1
                    fi
                fi
            else
                # Check field exists or expression is truthy
                if ! echo "$response" | jq -e "$assertion" >/dev/null 2>&1; then
                    log_fail "$test_name" "JSON assertion failed: $assertion"
                    return 1
                fi
            fi
        done <<< "$expect_json"
    fi

    log_pass "$test_name"
    return 0
}

# Parse and run tests from file
run_test_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error:${NC} Test file not found: $file"
        return 1
    fi

    echo -e "\n${BLUE}Running tests from:${NC} $file"
    echo "─────────────────────────────────────────"

    # Parse test definitions
    local test_name="" method="GET" path="" headers="" body=""
    local expect_status="" expect_body="" expect_json=""
    local in_test=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments outside tests
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Test separator - run previous test
        if [[ "$line" == "---" ]]; then
            if [[ "$in_test" == "true" ]] && [[ -n "$test_name" ]]; then
                run_test "$test_name" "$method" "$path" "$headers" "$body" \
                         "$expect_status" "$expect_body" "$expect_json"
            fi
            # Reset for next test
            test_name="" method="GET" path="" headers="" body=""
            expect_status="" expect_body="" expect_json=""
            in_test=false
            continue
        fi

        # Parse test definition lines
        case "$line" in
            TEST:*)
                test_name="${line#TEST:}"
                test_name="${test_name#"${test_name%%[![:space:]]*}"}"
                in_test=true
                ;;
            METHOD:*)
                method="${line#METHOD:}"
                method="${method#"${method%%[![:space:]]*}"}"
                ;;
            PATH:*)
                path="${line#PATH:}"
                path="${path#"${path%%[![:space:]]*}"}"
                ;;
            HEADERS:*)
                local header="${line#HEADERS:}"
                header="${header#"${header%%[![:space:]]*}"}"
                if [[ -n "$headers" ]]; then
                    headers="$headers"$'\n'"$header"
                else
                    headers="$header"
                fi
                ;;
            BODY:*)
                body="${line#BODY:}"
                body="${body#"${body%%[![:space:]]*}"}"
                ;;
            EXPECT_STATUS:*)
                expect_status="${line#EXPECT_STATUS:}"
                expect_status="${expect_status#"${expect_status%%[![:space:]]*}"}"
                ;;
            EXPECT_BODY:*)
                expect_body="${line#EXPECT_BODY:}"
                expect_body="${expect_body#"${expect_body%%[![:space:]]*}"}"
                ;;
            EXPECT_JSON:*)
                local json_assertion="${line#EXPECT_JSON:}"
                json_assertion="${json_assertion#"${json_assertion%%[![:space:]]*}"}"
                if [[ -n "$expect_json" ]]; then
                    expect_json="$expect_json"$'\n'"$json_assertion"
                else
                    expect_json="$json_assertion"
                fi
                ;;
        esac
    done < "$file"

    # Run last test if no trailing ---
    if [[ "$in_test" == "true" ]] && [[ -n "$test_name" ]]; then
        run_test "$test_name" "$method" "$path" "$headers" "$body" \
                 "$expect_status" "$expect_body" "$expect_json"
    fi
}

# Output results as JSON
output_json() {
    echo "{"
    echo "  \"total\": $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)),"
    echo "  \"passed\": $PASS_COUNT,"
    echo "  \"failed\": $FAIL_COUNT,"
    echo "  \"skipped\": $SKIP_COUNT,"
    echo "  \"tests\": ["
    local first=true
    for test in "${TESTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    $test"
    done
    echo ""
    echo "  ]"
    echo "}"
}

# Output results as JUnit XML
output_junit() {
    local total=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo "<testsuite name=\"API Tests\" tests=\"$total\" failures=\"$FAIL_COUNT\" skipped=\"$SKIP_COUNT\">"

    for test in "${TESTS[@]}"; do
        local name
        local status
        name=$(echo "$test" | jq -r '.name' 2>/dev/null)
        status=$(echo "$test" | jq -r '.status' 2>/dev/null)

        echo "  <testcase name=\"$name\">"
        if [[ "$status" == "fail" ]]; then
            local reason
            reason=$(echo "$test" | jq -r '.reason // ""' 2>/dev/null)
            echo "    <failure message=\"$reason\"/>"
        elif [[ "$status" == "skip" ]]; then
            echo "    <skipped/>"
        fi
        echo "  </testcase>"
    done

    echo "</testsuite>"
}

# Generate summary
generate_summary() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo -e "${BLUE}API Test Summary${NC}"
    echo "═══════════════════════════════════════════"
    echo -e "  ${GREEN}Passed:${NC}  $PASS_COUNT"
    echo -e "  ${RED}Failed:${NC}  $FAIL_COUNT"
    echo -e "  ${YELLOW}Skipped:${NC} $SKIP_COUNT"
    echo ""

    local total=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
    if [[ $total -gt 0 ]]; then
        local rate=$((PASS_COUNT * 100 / total))
        echo -e "Pass rate: ${BLUE}${rate}%${NC}"
    fi

    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}$FAIL_COUNT test(s) failed${NC}"
        return 1
    fi
}

# Quick test - test a single endpoint
quick_test() {
    local method="$1"
    local url="$2"
    local expect="${3:-200}"

    echo -e "${BLUE}Quick Test:${NC} $method $url"

    local response
    local http_code

    if ! response=$(curl -s -w "\n%{http_code}" -X "$method" --max-time "$TIMEOUT" "$url" 2>&1); then
        log_fail "Quick test" "Request failed"
        return 1
    fi

    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    echo "Status: $http_code"
    if [[ -n "$response" ]]; then
        echo "Response: ${response:0:500}"
    fi

    if [[ "$http_code" == "$expect" ]]; then
        echo -e "${GREEN}✓ Status matches expected ($expect)${NC}"
        return 0
    else
        echo -e "${RED}✗ Expected $expect, got $http_code${NC}"
        return 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u)
            BASE_URL="$2"
            shift 2
            ;;
        -t)
            TIMEOUT="$2"
            shift 2
            ;;
        -v)
            VERBOSE=true
            shift
            ;;
        -q)
            QUIET=true
            shift
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --junit)
            OUTPUT_FORMAT="junit"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            TEST_FILE="$1"
            shift
            ;;
    esac
done

# Main execution
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          API Test Runner v1.0             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo -e "Base URL: ${CYAN}$BASE_URL${NC}"

if [[ -z "$TEST_FILE" ]]; then
    echo ""
    echo "No test file specified. Use -h for help."
    echo ""
    echo "Example test file (tests/example.api-test):"
    echo "─────────────────────────────────────────"
    cat << 'EXAMPLE'
# Test health endpoint
TEST: Health check
METHOD: GET
PATH: /health
EXPECT_STATUS: 200
---

# Test API endpoint
TEST: Get users list
METHOD: GET
PATH: /api/users
EXPECT_STATUS: 200
EXPECT_JSON: .|type=="array"
---
EXAMPLE
    exit 0
fi

# Run tests
if [[ -d "$TEST_FILE" ]]; then
    # Run all test files in directory
    for file in "$TEST_FILE"/*.api-test "$TEST_FILE"/*.test; do
        [[ -f "$file" ]] || continue
        run_test_file "$file"
    done
else
    run_test_file "$TEST_FILE"
fi

# Output results
case "$OUTPUT_FORMAT" in
    json)
        output_json
        ;;
    junit)
        output_junit
        ;;
    *)
        generate_summary
        ;;
esac

exit $FAIL_COUNT
