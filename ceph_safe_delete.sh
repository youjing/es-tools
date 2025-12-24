#!/bin/bash

# Defaults
DRY_RUN=false
NO_CONFIRM=false
SLEEP_SEC=2
TRUNCATE_SIZE="10M"
TARGETS=()

# Detect OS for stat command
OS="$(uname)"
if [ "$OS" == "Darwin" ]; then
    STAT_CMD="stat -f%z"
else
    STAT_CMD="stat -c%s"
fi

usage() {
    echo "Usage: $(basename "$0") [--dry-run] [--help] [--sleep <seconds>] [--no-confirm] [--truncate-size <size>] <dir>|<file> ..."
    echo
    echo "Options:"
    echo "  --dry-run             Simulate deletion without making changes"
    echo "  --no-confirm          Skip confirmation prompt"
    echo "  --sleep <seconds>     Sleep duration after each truncate (default: 2)"
    echo "  --truncate-size <size> Size to truncate per iteration (default: 10M)"
    echo "  --help                Show this help message"
    echo
    echo "Arguments:"
    echo "  <dir>|<file>          File(s) or directory list to delete"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --dry-run)
            DRY_RUN=true
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
    
    echo "  Processing file: $file"
    
    # Get current size
    local current_size=$($STAT_CMD "$file")
    
    while [ "$current_size" -gt 0 ]; do
        if [ "$DRY_RUN" = true ]; then
            echo "    [DRY-RUN] Would truncate -s -${TRUNCATE_SIZE} $file (current: $current_size)"
            echo "    [DRY-RUN] Would sleep $SLEEP_SEC"
            break # In dry run, we don't loop forever
        else
            echo "    Truncating $file (current: $current_size) by ${TRUNCATE_SIZE}..."
            truncate -s "-${TRUNCATE_SIZE}" "$file" 2>/dev/null
            
            if [ $? -ne 0 ]; then
                echo "    Truncate failed or file small, clearing file."
                : > "$file"
            fi
            
            current_size=$($STAT_CMD "$file")
            echo "    Remaining size: $current_size. Sleeping ${SLEEP_SEC}s..."
            sleep "$SLEEP_SEC"
        fi
    done
    
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would remove file: $file"
    else
        rm -f "$file"
        echo "    Deleted file: $file"
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
             # Recursively remove the directory (should be empty of files now, but might have empty subdirs)
             # safe approach: remove empty subdirs then dir?
             # Or just rm -rf the dir structure since files are gone?
             # The user requirement implies "safe delete" of files.
             # Once files are safe-deleted (truncated), we can just rm -rf the dir to clear folder structure.
             rm -rf "$target"
             echo "Deleted directory: $target"
        fi
        
    else
        safe_delete_file "$target"
    fi
done

echo "Done."