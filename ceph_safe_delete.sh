#!/bin/bash

# Function: draw_progress_bar
# Description: Displays a progress bar on the current line.
# Usage: draw_progress_bar <current_value> <total_value> [bar_width]
# Example: draw_progress_bar 45 100
draw_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-50}" # Default width is 50 characters

    # Validate inputs
    if [ -z "$current" ] || [ -z "$total" ]; then
        return
    fi
    
    # Calculate percentage
    local percent=0
    if [ "$total" -gt 0 ]; then
        percent=$((current * 100 / total))
    fi
    
    # Ensure percent is between 0 and 100
    if [ "$percent" -lt 0 ]; then percent=0; fi
    if [ "$percent" -gt 100 ]; then percent=100; fi

    # Calculate number of filled and empty characters
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    # Generate the bar string
    local filled_bar=""
    if [ "$filled" -gt 0 ]; then
        filled_bar=$(printf "%0.s=" $(seq 1 "$filled"))
    fi
    
    local empty_bar=""
    if [ "$empty" -gt 0 ]; then
        empty_bar=$(printf "%0.s " $(seq 1 "$empty"))
    fi

    # Add an arrow head if the bar is not full and has at least 1 char
    if [ "$filled" -gt 0 ] && [ "$filled" -lt "$width" ]; then
        filled_bar="${filled_bar%?}>"
    fi

    local suffix="$4"

    # Print using \r (carriage return) to return to start of line
    # \033[K clears the line from the cursor to the end to prevent ghosting
    printf "\r[%s%s] %3d%% %s\033[K" "$filled_bar" "$empty_bar" "$percent" "$suffix"
}

# Defaults
DRY_RUN=false
NO_CONFIRM=false
SLEEP_SEC=2
TRUNCATE_SIZE="10M"
VERBOSE=false
TARGETS=()

# Detect OS for stat command
OS="$(uname)"
if [ "$OS" == "Darwin" ]; then
    STAT_CMD="stat -f%z"
else
    STAT_CMD="stat -c%s"
fi

usage() {
    echo "Usage: $(basename "$0") [--dry-run] [--verbose] [--help] [--sleep <seconds>] [--no-confirm] [--truncate-size <size>] <dir>|<file> ..."
    echo
    echo "Options:"
    echo "  --dry-run             Simulate deletion without making changes"
    echo "  --verbose             Show detailed truncation logs instead of progress bar"
    echo "  --no-confirm          Skip confirmation prompt"
    echo "  --sleep <seconds>     Sleep duration after each truncate (default: 2)"
    echo "  --truncate-size <size> Size to truncate per iteration (default: 10M)"
    echo "  --help                Show this help message"
    echo
    echo "Arguments:"
    echo "  <dir>|<file>          File(s) or directory list to delete"
    exit 0
}

format_size() {
    local bytes="${1:-0}"
    if [ "$bytes" -ge 1073741824 ]; then
        local total_tenths=$((bytes * 10 / 1073741824))
        local whole=$((total_tenths / 10))
        local decimal=$((total_tenths % 10))
        echo "${whole}.${decimal}G"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$((bytes / 1048576))M"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$((bytes / 1024))K"
    else
        echo "${bytes}B"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --no-confirm)
            NO_CONFIRM=true
            shift
            ;;
        --help)
            usage
            ;;
        --sleep)
            SLEEP_SEC="$2"
            shift ; shift
            ;;
        --truncate-size)
            TRUNCATE_SIZE="$2"
            shift ; shift
            ;;
        *)
            TARGETS+=("$1")
            shift
            ;;
    esac
done

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "Error: No targets specified."
    usage
fi

echo "Configuration:"
echo "  Dry Run:       $DRY_RUN"
echo "  Verbose:       $VERBOSE"
echo "  Sleep:         ${SLEEP_SEC}s"
echo "  Truncate Size: $TRUNCATE_SIZE"
echo "  Targets:       ${TARGETS[*]}"
echo

if [ "$DRY_RUN" = false ] && [ "$NO_CONFIRM" = false ]; then
    read -p "Are you sure you want to delete these ${#TARGETS[@]} items safely? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

safe_delete_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "  [SKIP] Not a file: $file"
        return
    fi
    
    # Get current size
    local current_size=$($STAT_CMD "$file")
    local initial_size=$current_size
    local initial_size_str=$(format_size $initial_size)
    
    echo "Processing file: $file, $initial_size_str"
    
    while [ "$current_size" -gt 0 ]; do
        if [ "$DRY_RUN" = true ]; then
            if [ "$VERBOSE" = true ]; then
                 echo "    [DRY-RUN] Would truncate -s -${TRUNCATE_SIZE} $file (current: $current_size)"
                 echo "    [DRY-RUN] Would sleep $SLEEP_SEC"
            else
                 # Mock progress for dry run
                 draw_progress_bar "50" "100" 40 ", (Dry Run Mock)"
                 echo ""
            fi
            break # In dry run, we don't loop forever
        else
            # Calculate info for progress/logs
            local deleted=$((initial_size - current_size))
            
            if [ "$VERBOSE" = true ]; then
                echo "    Truncating $file (current: $current_size) by ${TRUNCATE_SIZE}..."
                
                truncate -s "-${TRUNCATE_SIZE}" "$file" 2>/dev/null
                
                if [ $? -ne 0 ]; then
                    echo "    Truncate failed or file small, clearing file."
                    : > "$file"
                fi
                
                current_size=$($STAT_CMD "$file")
                echo "    Remaining size: $current_size. Sleeping ${SLEEP_SEC}s..."
            else
                # Progress bar mode
                local deleted_str=$(format_size $deleted)
                draw_progress_bar "$deleted" "$initial_size" 40 ", $deleted_str of $initial_size_str"
                
                truncate -s "-${TRUNCATE_SIZE}" "$file" 2>/dev/null
                
                if [ $? -ne 0 ]; then
                    : > "$file"
                fi
                
                current_size=$($STAT_CMD "$file")
            fi
            
            sleep "$SLEEP_SEC"
        fi
    done
    
    if [ "$DRY_RUN" = true ]; then
        if [ "$VERBOSE" = true ]; then
            echo "    [DRY-RUN] Would remove file: $file"
        else
            echo "    [DRY-RUN] Would remove file: $file"
        fi
    else
        rm -f "$file"
        if [ "$VERBOSE" = true ]; then
            echo "    Deleted file: $file"
        else
            # Clear the progress bar line and print deletion status
            # \033[K clears the line from cursor to end
            printf "\r\033[KDeleted file: %s.\n" "$file"
        fi
    fi
}

# 捕捉 Ctrl+C
trap 'echo -e "\n操作被用户中断"; exit 1' SIGINT

for target in "${TARGETS[@]}"; do
    if [ ! -e "$target" ]; then
        echo "Warning: '$target' not found"
        continue
    fi
    
    if [ -d "$target" ]; then
        echo "Entering directory: $target"
        # Use find to list all files and process them
        find "$target" -type f | while read -r file; do
            safe_delete_file "$file"
        done
        
        # Remove empty dir
        if [ "$DRY_RUN" = true ]; then
             echo "[DRY-RUN] Would remove directory tree: $target"
        else
             rm -rf "$target"
             echo "Deleted directory: $target"
        fi
        
    else
        safe_delete_file "$target"
    fi
done

echo "Done."