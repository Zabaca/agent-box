#!/bin/bash
#
# Text Diff Tool
# Compare files or text with colored, readable output
#
# Usage: diff-tool.sh [options] <file1> <file2>
#   -s, --side       Side-by-side comparison
#   -u, --unified    Unified diff format (default)
#   -w, --words      Word-level diff
#   -c, --chars      Character-level diff
#   --stats          Show statistics only
#   --json           Output as JSON
#   --html           Output as HTML
#   -i               Ignore case
#   -b               Ignore whitespace changes
#   -h, --help       Show help

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'

# Defaults
MODE="unified"
IGNORE_CASE=false
IGNORE_WHITESPACE=false
OUTPUT_FORMAT="text"
FILE1=""
FILE2=""

usage() {
    cat << 'EOF'
Text Diff Tool - Compare files with readable output

Usage: diff-tool.sh [options] <file1> <file2>
       echo "text1" | diff-tool.sh - <file2>

Options:
  -s, --side       Side-by-side comparison
  -u, --unified    Unified diff format (default)
  -w, --words      Word-level diff (highlight changed words)
  -c, --chars      Character-level diff
  --stats          Show statistics only
  --json           Output as JSON
  --html           Output as HTML
  -i               Ignore case differences
  -b               Ignore whitespace changes
  -C N             Context lines (default: 3)
  -h, --help       Show this help

Output Legend:
  + / green        Added lines
  - / red          Removed lines
  ~ / yellow       Modified lines

Examples:
  diff-tool.sh old.txt new.txt              # Basic diff
  diff-tool.sh -s config.old config.new     # Side by side
  diff-tool.sh -w doc1.md doc2.md           # Word diff
  diff-tool.sh --stats file1 file2          # Statistics only
  diff-tool.sh --html a.txt b.txt > diff.html

Piping:
  git show HEAD:file | diff-tool.sh - file   # Compare with git version
  curl -s url | diff-tool.sh local.txt -     # Compare with remote
EOF
}

# Read file or stdin
read_file() {
    local file="$1"
    if [[ "$file" == "-" ]]; then
        cat
    elif [[ -f "$file" ]]; then
        cat "$file"
    else
        echo "Error: File not found: $file" >&2
        return 1
    fi
}

# Unified diff with colors
unified_diff() {
    local file1="$1"
    local file2="$2"

    local diff_opts=("-u")
    $IGNORE_CASE && diff_opts+=("-i")
    $IGNORE_WHITESPACE && diff_opts+=("-b")

    diff "${diff_opts[@]}" "$file1" "$file2" 2>/dev/null | while IFS= read -r line; do
        case "${line:0:1}" in
            "+")
                if [[ "${line:0:3}" == "+++" ]]; then
                    echo -e "${BLUE}$line${NC}"
                else
                    echo -e "${GREEN}$line${NC}"
                fi
                ;;
            "-")
                if [[ "${line:0:3}" == "---" ]]; then
                    echo -e "${BLUE}$line${NC}"
                else
                    echo -e "${RED}$line${NC}"
                fi
                ;;
            "@")
                echo -e "${CYAN}$line${NC}"
                ;;
            *)
                echo "$line"
                ;;
        esac
    done
}

# Side-by-side diff
side_by_side_diff() {
    local file1="$1"
    local file2="$2"

    local diff_opts=("-y" "-W" "160")
    $IGNORE_CASE && diff_opts+=("-i")
    $IGNORE_WHITESPACE && diff_opts+=("-b")

    # Header
    local name1 name2
    name1=$(basename "$file1")
    name2=$(basename "$file2")
    printf "${BLUE}%-78s │ %-78s${NC}\n" "$name1" "$name2"
    printf "%.78s─┼─%.78s\n" "────────────────────────────────────────────────────────────────────────────────" "────────────────────────────────────────────────────────────────────────────────"

    diff "${diff_opts[@]}" "$file1" "$file2" 2>/dev/null | while IFS= read -r line; do
        # Detect change markers
        if [[ "$line" == *" | "* ]]; then
            # Changed line
            echo -e "${YELLOW}$line${NC}"
        elif [[ "$line" == *" < "* ]]; then
            # Only in left
            echo -e "${RED}$line${NC}"
        elif [[ "$line" == *" > "* ]]; then
            # Only in right
            echo -e "${GREEN}$line${NC}"
        else
            echo "$line"
        fi
    done
}

# Word-level diff
word_diff() {
    local file1="$1"
    local file2="$2"

    local diff_opts=("--word-diff=color")
    $IGNORE_CASE && diff_opts+=("-i")
    $IGNORE_WHITESPACE && diff_opts+=("-b")

    # Use git diff if available for better word diff
    if command -v git &>/dev/null; then
        git diff --no-index --word-diff=color "${diff_opts[@]}" "$file1" "$file2" 2>/dev/null | tail -n +5
    else
        # Fallback to wdiff if available
        if command -v wdiff &>/dev/null; then
            wdiff -n "$file1" "$file2" 2>/dev/null | \
                sed "s/\[-/${RED}/g; s/-\]/${NC}/g; s/{+/${GREEN}/g; s/+}/${NC}/g"
        else
            echo "Word diff requires git or wdiff"
            unified_diff "$file1" "$file2"
        fi
    fi
}

# Character-level diff
char_diff() {
    local file1="$1"
    local file2="$2"

    # Use git diff with character highlighting
    if command -v git &>/dev/null; then
        git diff --no-index --color-words=. "$file1" "$file2" 2>/dev/null | tail -n +5
    else
        unified_diff "$file1" "$file2"
    fi
}

# Statistics only
diff_stats() {
    local file1="$1"
    local file2="$2"

    local lines1 lines2 words1 words2 chars1 chars2
    lines1=$(wc -l < "$file1")
    lines2=$(wc -l < "$file2")
    words1=$(wc -w < "$file1")
    words2=$(wc -w < "$file2")
    chars1=$(wc -c < "$file1")
    chars2=$(wc -c < "$file2")

    # Count diff lines
    local added removed changed
    local diff_output
    diff_output=$(diff "$file1" "$file2" 2>/dev/null || true)
    added=$(echo "$diff_output" | grep -c "^>" || echo 0)
    removed=$(echo "$diff_output" | grep -c "^<" || echo 0)

    echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║            Diff Statistics                ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    printf "%-20s %15s %15s %15s\n" "" "$(basename "$file1")" "$(basename "$file2")" "Diff"
    echo "─────────────────────────────────────────────────────────────────"
    printf "%-20s %15d %15d %+15d\n" "Lines" "$lines1" "$lines2" "$((lines2 - lines1))"
    printf "%-20s %15d %15d %+15d\n" "Words" "$words1" "$words2" "$((words2 - words1))"
    printf "%-20s %15d %15d %+15d\n" "Characters" "$chars1" "$chars2" "$((chars2 - chars1))"
    echo ""
    echo -e "${GREEN}Added lines:${NC}   $added"
    echo -e "${RED}Removed lines:${NC} $removed"

    # Similarity percentage
    local total=$((lines1 + lines2))
    if [[ $total -gt 0 ]]; then
        local changed_total=$((added + removed))
        local similarity=$((100 - (changed_total * 100 / total)))
        echo ""
        echo -e "Similarity: ${CYAN}${similarity}%${NC}"
    fi
}

# JSON output
json_diff() {
    local file1="$1"
    local file2="$2"

    local lines1 lines2 added removed
    lines1=$(wc -l < "$file1")
    lines2=$(wc -l < "$file2")

    local diff_output
    diff_output=$(diff "$file1" "$file2" 2>/dev/null || true)
    added=$(echo "$diff_output" | grep -c "^>" || echo 0)
    removed=$(echo "$diff_output" | grep -c "^<" || echo 0)

    echo "{"
    echo "  \"file1\": \"$file1\","
    echo "  \"file2\": \"$file2\","
    echo "  \"stats\": {"
    echo "    \"lines1\": $lines1,"
    echo "    \"lines2\": $lines2,"
    echo "    \"added\": $added,"
    echo "    \"removed\": $removed"
    echo "  },"
    echo "  \"identical\": $([ "$added" -eq 0 ] && [ "$removed" -eq 0 ] && echo "true" || echo "false"),"
    echo "  \"hunks\": ["

    # Parse diff into hunks
    local first=true
    local hunk_start=0
    local hunk_lines=""

    diff -u "$file1" "$file2" 2>/dev/null | while IFS= read -r line; do
        if [[ "$line" =~ ^@@.*@@ ]]; then
            if [[ -n "$hunk_lines" ]]; then
                $first || echo ","
                echo "    {\"header\": \"$hunk_start\", \"changes\": $hunk_lines}"
                first=false
            fi
            hunk_start="$line"
            hunk_lines="[]"
        elif [[ "$line" =~ ^[+-] ]] && [[ ! "$line" =~ ^[+-]{3} ]]; then
            local type="context"
            [[ "${line:0:1}" == "+" ]] && type="add"
            [[ "${line:0:1}" == "-" ]] && type="remove"
            local content="${line:1}"
            content="${content//\\/\\\\}"
            content="${content//\"/\\\"}"
            # Simplified - just count
        fi
    done

    echo "  ]"
    echo "}"
}

# HTML output
html_diff() {
    local file1="$1"
    local file2="$2"

    cat << 'HTML_HEAD'
<!DOCTYPE html>
<html>
<head>
    <title>Diff Output</title>
    <style>
        body { font-family: monospace; background: #1e1e1e; color: #d4d4d4; padding: 20px; }
        .diff { border: 1px solid #333; border-radius: 4px; overflow: hidden; }
        .header { background: #252526; padding: 10px; border-bottom: 1px solid #333; }
        .line { padding: 2px 10px; white-space: pre; }
        .add { background: rgba(0, 255, 0, 0.1); color: #89d185; }
        .remove { background: rgba(255, 0, 0, 0.1); color: #f14c4c; }
        .hunk { background: #264f78; color: #9cdcfe; }
        .line-num { color: #858585; margin-right: 10px; display: inline-block; width: 40px; }
    </style>
</head>
<body>
    <h2>Diff: $(basename "$file1") → $(basename "$file2")</h2>
    <div class="diff">
HTML_HEAD

    diff -u "$file1" "$file2" 2>/dev/null | while IFS= read -r line; do
        local class=""
        case "${line:0:1}" in
            "+")
                [[ "${line:0:3}" != "+++" ]] && class="add"
                ;;
            "-")
                [[ "${line:0:3}" != "---" ]] && class="remove"
                ;;
            "@")
                class="hunk"
                ;;
        esac
        # HTML escape
        line="${line//&/&amp;}"
        line="${line//</&lt;}"
        line="${line//>/&gt;}"
        echo "        <div class=\"line $class\">$line</div>"
    done

    cat << 'HTML_FOOT'
    </div>
</body>
</html>
HTML_FOOT
}

# Parse arguments
CONTEXT=3
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--side)
            MODE="side"
            shift
            ;;
        -u|--unified)
            MODE="unified"
            shift
            ;;
        -w|--words)
            MODE="words"
            shift
            ;;
        -c|--chars)
            MODE="chars"
            shift
            ;;
        --stats)
            MODE="stats"
            shift
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --html)
            OUTPUT_FORMAT="html"
            shift
            ;;
        -i)
            IGNORE_CASE=true
            shift
            ;;
        -b)
            IGNORE_WHITESPACE=true
            shift
            ;;
        -C)
            CONTEXT="$2"
            shift 2
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
            if [[ -z "$FILE1" ]]; then
                FILE1="$1"
            elif [[ -z "$FILE2" ]]; then
                FILE2="$1"
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [[ -z "$FILE1" || -z "$FILE2" ]]; then
    usage
    exit 1
fi

# Handle stdin
TEMP1=""
TEMP2=""
if [[ "$FILE1" == "-" ]]; then
    TEMP1=$(mktemp)
    cat > "$TEMP1"
    FILE1="$TEMP1"
fi
if [[ "$FILE2" == "-" ]]; then
    TEMP2=$(mktemp)
    cat > "$TEMP2"
    FILE2="$TEMP2"
fi

# Validate files exist
if [[ ! -f "$FILE1" ]]; then
    echo "Error: File not found: $FILE1" >&2
    exit 1
fi
if [[ ! -f "$FILE2" ]]; then
    echo "Error: File not found: $FILE2" >&2
    exit 1
fi

# Check if files are identical
if diff -q "$FILE1" "$FILE2" &>/dev/null; then
    echo -e "${GREEN}Files are identical${NC}"
    [[ -n "$TEMP1" ]] && rm -f "$TEMP1"
    [[ -n "$TEMP2" ]] && rm -f "$TEMP2"
    exit 0
fi

# Run appropriate diff mode
case "$OUTPUT_FORMAT" in
    json)
        json_diff "$FILE1" "$FILE2"
        ;;
    html)
        html_diff "$FILE1" "$FILE2"
        ;;
    *)
        case "$MODE" in
            unified)
                unified_diff "$FILE1" "$FILE2"
                ;;
            side)
                side_by_side_diff "$FILE1" "$FILE2"
                ;;
            words)
                word_diff "$FILE1" "$FILE2"
                ;;
            chars)
                char_diff "$FILE1" "$FILE2"
                ;;
            stats)
                diff_stats "$FILE1" "$FILE2"
                ;;
        esac
        ;;
esac

# Cleanup temp files
[[ -n "$TEMP1" ]] && rm -f "$TEMP1"
[[ -n "$TEMP2" ]] && rm -f "$TEMP2"
