#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# Function to compute the hash of a file
compute_hash() {
    local file=$1
    sha256sum "$file" | awk '{ print $1 }'
}

# Function to compute and log the hash of the script and other source files
log_script_hash() {
    local script_hash=$(compute_hash "install_miniprem.sh")
    local other_files=("scripts/audio.sh" "scripts/docker.sh" "scripts/logging.sh" "scripts/hash.sh" "scripts/environment.sh" "scripts/prerequisites.sh")
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