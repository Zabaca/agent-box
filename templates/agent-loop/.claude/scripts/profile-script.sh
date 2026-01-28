#!/bin/bash
#
# Script Performance Profiler
# Measure and analyze shell script execution performance
#
# Usage: profile-script.sh <command> [options]
#   run <script> [args]       Profile script execution
#   time <script> [args]      Simple timing (multiple runs)
#   trace <script> [args]     Trace with timestamps
#   compare <s1> <s2>         Compare two scripts
#   benchmark <script>        Run comprehensive benchmark
#   -h, --help                Show help

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat << 'EOF'
Script Performance Profiler - Measure script execution

Usage: profile-script.sh <command> [options]

Commands:
  run <script> [args]       Profile single execution with detailed metrics
  time <script> [args]      Time multiple runs, show statistics
  trace <script> [args]     Line-by-line timing trace
  compare <s1> <s2> [args]  Compare performance of two scripts
  benchmark <script>        Comprehensive performance benchmark
  memory <script> [args]    Track memory usage during execution

Options:
  -n <count>                Number of runs for timing (default: 5)
  -o <file>                 Output results to file
  --csv                     Output in CSV format
  --json                    Output in JSON format
  -v, --verbose             Show detailed output
  -h, --help                Show this help

Metrics Collected:
  - Wall clock time (real)
  - CPU time (user + system)
  - Memory usage (peak RSS)
  - I/O operations
  - Process counts

Examples:
  profile-script.sh run ./myscript.sh arg1 arg2
  profile-script.sh time -n 10 ./myscript.sh
  profile-script.sh trace ./myscript.sh
  profile-script.sh compare ./v1.sh ./v2.sh
  profile-script.sh benchmark ./myscript.sh
EOF
}

# Get high-precision timestamp
get_timestamp() {
    date +%s.%N
}

# Calculate time difference
time_diff() {
    local start="$1"
    local end="$2"
    echo "scale=6; $end - $start" | bc
}

# Format duration
format_duration() {
    local seconds="$1"
    if (( $(echo "$seconds < 0.001" | bc -l) )); then
        echo "$(echo "scale=3; $seconds * 1000000" | bc)μs"
    elif (( $(echo "$seconds < 1" | bc -l) )); then
        echo "$(echo "scale=3; $seconds * 1000" | bc)ms"
    elif (( $(echo "$seconds < 60" | bc -l) )); then
        echo "${seconds}s"
    else
        local mins
        mins=$(echo "scale=0; $seconds / 60" | bc)
        local secs
        secs=$(echo "scale=2; $seconds - ($mins * 60)" | bc)
        echo "${mins}m ${secs}s"
    fi
}

# Profile single execution
cmd_run() {
    local script="$1"
    shift
    local args=("$@")

    if [[ ! -f "$script" ]]; then
        echo -e "${RED}Error:${NC} Script not found: $script"
        return 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Profiling: $(basename "$script")"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local start_time
    start_time=$(get_timestamp)

    # Use /usr/bin/time for detailed stats
    local time_output
    time_output=$(mktemp)

    if command -v /usr/bin/time &>/dev/null; then
        /usr/bin/time -v bash "$script" "${args[@]}" 2>"$time_output"
        local exit_code=$?
    else
        # Fallback to bash time
        { time bash "$script" "${args[@]}"; } 2>"$time_output"
        local exit_code=$?
    fi

    local end_time
    end_time=$(get_timestamp)

    local wall_time
    wall_time=$(time_diff "$start_time" "$end_time")

    echo ""
    echo -e "${CYAN}Performance Results:${NC}"
    echo "─────────────────────────────────────────"
    echo -e "  Wall time:    ${GREEN}$(format_duration "$wall_time")${NC}"

    # Parse /usr/bin/time output if available
    if grep -q "Maximum resident" "$time_output" 2>/dev/null; then
        local user_time sys_time max_rss
        user_time=$(grep "User time" "$time_output" | awk '{print $NF}')
        sys_time=$(grep "System time" "$time_output" | awk '{print $NF}')
        max_rss=$(grep "Maximum resident" "$time_output" | awk '{print $NF}')

        echo "  CPU user:     ${user_time}s"
        echo "  CPU system:   ${sys_time}s"
        echo "  Peak memory:  $(echo "scale=2; $max_rss / 1024" | bc)MB"

        # I/O stats
        local vol_ctx inv_ctx
        vol_ctx=$(grep "Voluntary context" "$time_output" | awk '{print $NF}')
        inv_ctx=$(grep "Involuntary context" "$time_output" | awk '{print $NF}')
        echo "  Context switches: $vol_ctx voluntary, $inv_ctx involuntary"
    fi

    echo ""
    echo -e "  Exit code:    $exit_code"

    rm -f "$time_output"

    return $exit_code
}

# Time multiple runs
cmd_time() {
    local runs=5
    local script=""
    local args=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            -n)
                runs="$2"
                shift 2
                ;;
            *)
                if [[ -z "$script" ]]; then
                    script="$1"
                else
                    args+=("$1")
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$script" || ! -f "$script" ]]; then
        echo -e "${RED}Error:${NC} Script not found: $script"
        return 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Timing: $(basename "$script") ($runs runs)"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local times=()
    local sum=0

    for ((i=1; i<=runs; i++)); do
        echo -n "  Run $i/$runs: "

        local start
        start=$(get_timestamp)
        bash "$script" "${args[@]}" >/dev/null 2>&1
        local end
        end=$(get_timestamp)

        local duration
        duration=$(time_diff "$start" "$end")
        times+=("$duration")
        sum=$(echo "$sum + $duration" | bc)

        echo "$(format_duration "$duration")"
    done

    echo ""
    echo -e "${CYAN}Statistics:${NC}"
    echo "─────────────────────────────────────────"

    # Calculate statistics
    local avg
    avg=$(echo "scale=6; $sum / $runs" | bc)

    # Sort for min/max/median
    local sorted_times
    sorted_times=($(printf '%s\n' "${times[@]}" | sort -n))
    local min_time="${sorted_times[0]}"
    local max_time="${sorted_times[$((runs-1))]}"

    # Median
    local median
    if ((runs % 2 == 1)); then
        median="${sorted_times[$((runs/2))]}"
    else
        local mid1="${sorted_times[$((runs/2-1))]}"
        local mid2="${sorted_times[$((runs/2))]}"
        median=$(echo "scale=6; ($mid1 + $mid2) / 2" | bc)
    fi

    # Standard deviation
    local variance=0
    for t in "${times[@]}"; do
        local diff
        diff=$(echo "scale=6; ($t - $avg)^2" | bc)
        variance=$(echo "scale=6; $variance + $diff" | bc)
    done
    variance=$(echo "scale=6; $variance / $runs" | bc)
    local stddev
    stddev=$(echo "scale=6; sqrt($variance)" | bc)

    echo -e "  Average:    ${GREEN}$(format_duration "$avg")${NC}"
    echo "  Median:     $(format_duration "$median")"
    echo "  Min:        $(format_duration "$min_time")"
    echo "  Max:        $(format_duration "$max_time")"
    echo "  Std Dev:    $(format_duration "$stddev")"
}

# Trace execution with timestamps
cmd_trace() {
    local script="$1"
    shift
    local args=("$@")

    if [[ ! -f "$script" ]]; then
        echo -e "${RED}Error:${NC} Script not found: $script"
        return 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Tracing: $(basename "$script")"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Create trace script
    local trace_file
    trace_file=$(mktemp)

    cat > "$trace_file" << 'TRACE'
#!/bin/bash
_profile_start=$(date +%s.%N)
_profile_last=$_profile_start

_profile_trap() {
    local now=$(date +%s.%N)
    local elapsed=$(echo "scale=6; $now - $_profile_last" | bc)
    local total=$(echo "scale=6; $now - $_profile_start" | bc)
    printf "%10.6fs (+%10.6fs) %s:%s: %s\n" "$total" "$elapsed" "${BASH_SOURCE[1]##*/}" "$BASH_LINENO" "$BASH_COMMAND"
    _profile_last=$now
}

set -o functrace
trap '_profile_trap' DEBUG
TRACE

    # Append original script
    cat "$script" >> "$trace_file"

    echo -e "${CYAN}Execution trace:${NC}"
    echo "─────────────────────────────────────────"
    bash "$trace_file" "${args[@]}" 2>&1 | head -50

    rm -f "$trace_file"
}

# Compare two scripts
cmd_compare() {
    local script1="$1"
    local script2="$2"
    shift 2
    local args=("$@")
    local runs=5

    if [[ ! -f "$script1" || ! -f "$script2" ]]; then
        echo -e "${RED}Error:${NC} Script not found"
        return 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Comparing Scripts ($runs runs each)"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Time first script
    echo -e "${CYAN}Script 1: $(basename "$script1")${NC}"
    local sum1=0
    for ((i=1; i<=runs; i++)); do
        local start=$(get_timestamp)
        bash "$script1" "${args[@]}" >/dev/null 2>&1
        local end=$(get_timestamp)
        sum1=$(echo "$sum1 + $(time_diff "$start" "$end")" | bc)
    done
    local avg1=$(echo "scale=6; $sum1 / $runs" | bc)
    echo "  Average: $(format_duration "$avg1")"

    # Time second script
    echo ""
    echo -e "${CYAN}Script 2: $(basename "$script2")${NC}"
    local sum2=0
    for ((i=1; i<=runs; i++)); do
        local start=$(get_timestamp)
        bash "$script2" "${args[@]}" >/dev/null 2>&1
        local end=$(get_timestamp)
        sum2=$(echo "$sum2 + $(time_diff "$start" "$end")" | bc)
    done
    local avg2=$(echo "scale=6; $sum2 / $runs" | bc)
    echo "  Average: $(format_duration "$avg2")"

    # Comparison
    echo ""
    echo -e "${CYAN}Comparison:${NC}"
    echo "─────────────────────────────────────────"

    local diff_raw
    diff_raw=$(echo "scale=6; $avg2 - $avg1" | bc)
    local diff_pct
    diff_pct=$(echo "scale=2; (($avg2 - $avg1) / $avg1) * 100" | bc 2>/dev/null || echo "0")

    if (( $(echo "$diff_raw > 0" | bc -l) )); then
        echo -e "  Script 1 is ${GREEN}$(format_duration "${diff_raw#-}")${NC} faster (${diff_pct#-}%)"
    elif (( $(echo "$diff_raw < 0" | bc -l) )); then
        echo -e "  Script 2 is ${GREEN}$(format_duration "${diff_raw#-}")${NC} faster (${diff_pct#-}%)"
    else
        echo "  Scripts have similar performance"
    fi
}

# Comprehensive benchmark
cmd_benchmark() {
    local script="$1"
    shift
    local args=("$@")

    if [[ ! -f "$script" ]]; then
        echo -e "${RED}Error:${NC} Script not found: $script"
        return 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Comprehensive Benchmark: $(basename "$script")"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Warmup run
    echo -e "${GRAY}Warmup run...${NC}"
    bash "$script" "${args[@]}" >/dev/null 2>&1

    # Multiple timing runs
    echo ""
    echo -e "${CYAN}Timing (10 runs):${NC}"
    local times=()
    for ((i=1; i<=10; i++)); do
        local start=$(get_timestamp)
        bash "$script" "${args[@]}" >/dev/null 2>&1
        local end=$(get_timestamp)
        times+=("$(time_diff "$start" "$end")")
        echo -n "."
    done
    echo ""

    # Calculate stats
    local sum=0
    for t in "${times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    local avg=$(echo "scale=6; $sum / 10" | bc)

    local sorted=($(printf '%s\n' "${times[@]}" | sort -n))
    local min="${sorted[0]}"
    local max="${sorted[9]}"
    local p50="${sorted[4]}"
    local p95="${sorted[9]}"
    local p99="${sorted[9]}"

    echo ""
    echo -e "${CYAN}Timing Results:${NC}"
    echo "─────────────────────────────────────────"
    echo -e "  Average:   ${GREEN}$(format_duration "$avg")${NC}"
    echo "  Min:       $(format_duration "$min")"
    echo "  Max:       $(format_duration "$max")"
    echo "  P50:       $(format_duration "$p50")"
    echo "  P95/P99:   $(format_duration "$p95")"

    # Resource usage (single detailed run)
    echo ""
    echo -e "${CYAN}Resource Usage:${NC}"
    echo "─────────────────────────────────────────"

    if command -v /usr/bin/time &>/dev/null; then
        local time_output=$(mktemp)
        /usr/bin/time -v bash "$script" "${args[@]}" >/dev/null 2>"$time_output"

        local max_rss=$(grep "Maximum resident" "$time_output" | awk '{print $NF}' || echo "0")
        local vol_ctx=$(grep "Voluntary context" "$time_output" | awk '{print $NF}' || echo "0")
        local file_in=$(grep "File system inputs" "$time_output" | awk '{print $NF}' || echo "0")
        local file_out=$(grep "File system outputs" "$time_output" | awk '{print $NF}' || echo "0")

        echo "  Peak memory:  $(echo "scale=2; $max_rss / 1024" | bc 2>/dev/null || echo "0")MB"
        echo "  Context switches: $vol_ctx"
        echo "  File I/O:     $file_in inputs, $file_out outputs"

        rm -f "$time_output"
    else
        echo "  (Install /usr/bin/time for detailed resource stats)"
    fi

    # Script analysis
    echo ""
    echo -e "${CYAN}Script Analysis:${NC}"
    echo "─────────────────────────────────────────"
    local lines=$(wc -l < "$script")
    local size=$(stat --printf="%s" "$script" 2>/dev/null || stat -f%z "$script" 2>/dev/null || echo "0")
    local func_count=$(grep -cE '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$script" || echo 0)
    local subshell_count=$(grep -cE '\$\(' "$script" || echo 0)

    echo "  Lines:       $lines"
    echo "  Size:        $size bytes"
    echo "  Functions:   $func_count"
    echo "  Subshells:   $subshell_count"
}

# Track memory usage
cmd_memory() {
    local script="$1"
    shift
    local args=("$@")

    if [[ ! -f "$script" ]]; then
        echo -e "${RED}Error:${NC} Script not found: $script"
        return 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Memory Profile: $(basename "$script")"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Start script in background
    bash "$script" "${args[@]}" &
    local pid=$!

    local max_rss=0
    local samples=0

    echo -e "${CYAN}Memory samples (during execution):${NC}"
    while kill -0 $pid 2>/dev/null; do
        local rss=$(ps -o rss= -p $pid 2>/dev/null || echo 0)
        rss=${rss:-0}
        ((samples++))

        if [[ $rss -gt $max_rss ]]; then
            max_rss=$rss
        fi

        if ((samples % 10 == 0)); then
            echo "  Sample $samples: $(echo "scale=2; $rss / 1024" | bc)MB"
        fi

        sleep 0.1
    done

    wait $pid 2>/dev/null

    echo ""
    echo -e "${CYAN}Memory Results:${NC}"
    echo "─────────────────────────────────────────"
    echo "  Samples taken: $samples"
    echo -e "  Peak RSS:      ${GREEN}$(echo "scale=2; $max_rss / 1024" | bc)MB${NC}"
}

# Main command dispatch
RUNS=5
OUTPUT=""
FORMAT="text"
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n)
            RUNS="$2"
            shift 2
            ;;
        -o)
            OUTPUT="$2"
            shift 2
            ;;
        --csv|--json)
            FORMAT="${1#--}"
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        run|time|trace|compare|benchmark|memory)
            CMD="$1"
            shift
            break
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

case "${CMD:-run}" in
    run)
        if [[ $# -lt 1 ]]; then
            echo "Usage: profile-script.sh run <script> [args]"
            exit 1
        fi
        cmd_run "$@"
        ;;
    time)
        cmd_time "$@"
        ;;
    trace)
        if [[ $# -lt 1 ]]; then
            echo "Usage: profile-script.sh trace <script> [args]"
            exit 1
        fi
        cmd_trace "$@"
        ;;
    compare)
        if [[ $# -lt 2 ]]; then
            echo "Usage: profile-script.sh compare <script1> <script2> [args]"
            exit 1
        fi
        cmd_compare "$@"
        ;;
    benchmark)
        if [[ $# -lt 1 ]]; then
            echo "Usage: profile-script.sh benchmark <script>"
            exit 1
        fi
        cmd_benchmark "$@"
        ;;
    memory)
        if [[ $# -lt 1 ]]; then
            echo "Usage: profile-script.sh memory <script> [args]"
            exit 1
        fi
        cmd_memory "$@"
        ;;
    *)
        usage
        ;;
esac
