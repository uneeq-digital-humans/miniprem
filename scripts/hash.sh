#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# Function to compute the hash of a file
compute_hash() {
    local file=$1
    sha256sum "$file" | awk '{ print $1 }'
}

# Function to compute and log the hash of the script and other source files
log_script_hash() {
    # Use absolute paths based on PROJECT_ROOT which is set in install_miniprem.sh
    local script_path="$PROJECT_ROOT/docker/scripts/install_miniprem.sh"
    local script_hash=$(compute_hash "$script_path")
    local other_files=("$PROJECT_ROOT/scripts/audio.sh" "$PROJECT_ROOT/scripts/docker.sh" "$PROJECT_ROOT/scripts/logging.sh" "$PROJECT_ROOT/scripts/hash.sh" "$PROJECT_ROOT/scripts/environment.sh" "$PROJECT_ROOT/scripts/prerequisites.sh")
    local combined_hashes="$script_hash"

    for file in "${other_files[@]}"; do
        if [ -f "$file" ]; then
            local file_hash=$(compute_hash "$file")
            if [ $? -eq 0 ]; then
                combined_hashes="$combined_hashes $file_hash"
            else
                echo "Failed to compute hash for $file"
            fi
        else
            echo "File $file does not exist. Cannot compute hash."
        fi
    done

    local final_hash=$(echo -n "$combined_hashes" | sha256sum | awk '{ print $1 }')
    info "Combined script hash: $final_hash"
}

# Call the log_script_hash function at the start of the script
log_script_hash