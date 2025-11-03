#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# Function to read existing values from the .env file
read_env_variable() {
    local var_name="$1"
    local env_file="docker/docker-compose.env"
    local value=""

    if [ -f "$env_file" ]; then
        value=$(grep "^${var_name}=" "$env_file" | cut -d '=' -f 2-)
        value=$(echo "$value" | sed 's/^"//;s/"$//') # Remove surrounding quotes if any
    fi

    echo "$value"
}

# Function to update an environment variable in the .env file
update_env_variable() {
    local var_name="$1"
    local new_value="$2"
    local env_file="docker/docker-compose.env"

    # Ensure the file exists
    if [[ ! -f "$env_file" ]]; then
        touch "$env_file"
    fi

    # Check if file is empty or doesn't end with newline
    if [[ ! -s "$env_file" ]] || [[ $(tail -c 1 "$env_file" | wc -l) -eq 0 ]]; then
        # File is empty or doesn't end with newline, no need to add one
        :
    else
        # Ensure there's a newline at the end of the file
        echo "" >> "$env_file"
    fi

    if grep -q "^${var_name}=" "$env_file"; then
        # Update the existing variable
        sed -i "s|^${var_name}=.*|${var_name}=${new_value}|" "$env_file"
    else
        # Add the variable if it does not exist
        echo "${var_name}=${new_value}" >> "$env_file"
    fi
}