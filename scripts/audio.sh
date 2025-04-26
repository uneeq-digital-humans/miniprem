#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# Function to get the default sink (speaker)
get_default_sink() {
    pactl info | grep 'Default Sink' | cut -d ' ' -f 3
}

# Function to get the description of a sink
get_sink_description() {
    local sink=$1
    pactl list sinks | grep -A 20 "Name: $sink" | grep 'Description' | cut -d ':' -f 2 | xargs
}

# Function to get the default source (microphone)
get_default_source() {
    pactl info | grep 'Default Source' | cut -d ' ' -f 3
}

# Function to get the description of a source
get_source_description() {
    local source=$1
    pactl list sources | grep -A 20 "Name: $source" | grep 'Description' | cut -d ':' -f 2 | xargs
}

get_audio_playback_device() {
    local sink=$(get_default_sink)
    local description=$(get_sink_description $sink)
    echo "$description"
}

get_audio_recording_device() {
    local source=$(get_default_source)
    local description=$(get_source_description $source)
    echo "$description"
}