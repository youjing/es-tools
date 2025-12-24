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

    # Print using \r (carriage return) to return to start of line
    # No newline at the end
    printf "\r[%s%s] %3d%%" "$filled_bar" "$empty_bar" "$percent"
}

# Demo execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Progress Bar Demo:"
    TOTAL_STEPS=50
    for ((i=0; i<=TOTAL_STEPS; i++)); do
        draw_progress_bar "$i" "$TOTAL_STEPS" 40
        sleep 0.05
    done
    echo "" # New line after completion
    echo "Demo Complete."
fi
