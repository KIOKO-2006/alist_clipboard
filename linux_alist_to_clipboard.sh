#!/bin/bash
# Script to download content from Alist server to clipboard
# Supports both Wayland and X11 environments

# Load environment variables from .env file
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Set default values if not defined in .env
ALIST_SERVER=${ALIST_SERVER:-"http://localhost:5244"}
ALIST_USERNAME=${ALIST_USERNAME:-"admin"}
ALIST_PASSWORD=${ALIST_PASSWORD:-"password"}
ALIST_CLIPBOARD_DIR=${ALIST_CLIPBOARD_DIR:-"/host/clipboard"}
ALIST_TOKEN=${ALIST_TOKEN:-""}

# Function to detect display server
detect_display_server() {
    if [ -n "$WAYLAND_DISPLAY" ]; then
        echo "wayland"
    elif [ -n "$DISPLAY" ]; then
        echo "x11"
    else
        echo "unknown"
    fi
}

# Function to set clipboard on Wayland
set_wayland_clipboard() {
    local content="$1"
    local is_binary=$2
    local temp_file="$3"
    
    if ! command -v wl-copy &> /dev/null; then
        echo "Error: wl-clipboard is not installed. Install with: sudo pacman -S wl-clipboard" >&2
        return 1
    fi
    
    if [ "$is_binary" = true ]; then
        # For binary data (image)
        if [ -f "$temp_file" ]; then
            wl-copy < "$temp_file"
            rm -f "$temp_file"  # Clean up
            return $?
        else
            echo "Error: No temp file provided for binary data" >&2
            return 1
        fi
    else
        # For text data
        echo "$content" | wl-copy
        return $?
    fi
}

# Function to set clipboard on X11
set_x11_clipboard() {
    local content="$1"
    local is_binary=$2
    local temp_file="$3"
    
    if ! command -v xclip &> /dev/null; then
        echo "Error: xclip is not installed. Install with: sudo pacman -S xclip" >&2
        return 1
    fi
    
    if [ "$is_binary" = true ]; then
        # For binary data (image)
        if [ -f "$temp_file" ]; then
            xclip -selection clipboard -t image/png -i "$temp_file"
            rm -f "$temp_file"  # Clean up
            return $?
        else
            echo "Error: No temp file provided for binary data" >&2
            return 1
        fi
    else
        # For text data
        echo "$content" | xclip -selection clipboard -i
        return $?
    fi
}

# Function to set clipboard content
set_clipboard_content() {
    local content="$1"
    local is_binary=$2
    local temp_file="$3"
    
    local display_server=$(detect_display_server)
    
    if [ "$display_server" = "wayland" ]; then
        echo "Detected Wayland display server" >&2
        set_wayland_clipboard "$content" $is_binary "$temp_file"
    elif [ "$display_server" = "x11" ]; then
        echo "Detected X11 display server" >&2
        set_x11_clipboard "$content" $is_binary "$temp_file"
    else
        echo "Error: Could not detect display server" >&2
        return 1
    fi
}

# Function to login to Alist and get token
alist_login() {
    if [ -n "$ALIST_TOKEN" ]; then
        return 0
    fi
    
    echo "Logging in to Alist server..." >&2
    
    local login_data="{\"username\":\"$ALIST_USERNAME\",\"password\":\"$ALIST_PASSWORD\"}"
    local response=$(curl -s -X POST "$ALIST_SERVER/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "$login_data")
    
    # Extract token from response using grep and cut
    ALIST_TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d':' -f2 | tr -d '"')
    
    if [ -n "$ALIST_TOKEN" ]; then
        echo "Successfully logged in to Alist server" >&2
        return 0
    else
        echo "Failed to login to Alist server" >&2
        return 1
    fi
}

# Function to list files in Alist directory
list_files() {
    local path="$1"
    
    echo "Listing files in: $path" >&2
    
    local list_data="{\"path\":\"$path\",\"password\":\"\",\"page\":1,\"per_page\":100,\"refresh\":true}"
    local response=$(curl -s -X POST "$ALIST_SERVER/api/fs/list" \
        -H "Content-Type: application/json" \
        -H "Authorization: $ALIST_TOKEN" \
        -d "$list_data")
    
    echo "Debug - API Response: $response" >&2
    
    # Check if successful
    if ! echo "$response" | grep -q '"code":200'; then
        echo "Failed to list files" >&2
        echo "Response: $response" >&2
        return 1
    fi
    
    echo "$response"
    return 0
}

# Function to get latest file in directory
get_latest_file() {
    local path="$1"
    
    local files_json=$(list_files "$path")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "Debug - Processing API response: $files_json" >&2
    
    # Parse JSON to get files
    local files=$(echo "$files_json" | grep -o '"content":\[.*\]' | sed 's/"content"://')
    
    if [ -z "$files" ] || [ "$files" = "[]" ]; then
        echo "No files found in directory" >&2
        return 1
    fi
    
    echo "Debug - Content array: $files" >&2
    
    # Extract file entries - improved to handle complex JSON
    local entries_without_brackets=$(echo "$files" | sed 's/^\[//;s/\]$//')
    local IFS="}"
    local entries=($entries_without_brackets)
    
    # Initialize variables for tracking latest file
    local latest_file=""
    local latest_time=""
    
    # Process each file entry
    for entry in "${entries[@]}"; do
        # Add closing brace back if it was removed (except for last empty element)
        if [ -n "$entry" ]; then
            if [[ "$entry" != *"}"* ]]; then
                entry="$entry}"
            fi
            
            # Skip if not a file
            if echo "$entry" | grep -q '"is_dir":true'; then
                continue
            fi
            
            # Extract modified time and name
            local modified=$(echo "$entry" | grep -o '"modified":"[^"]*"' | cut -d':' -f2- | tr -d '"')
            local name=$(echo "$entry" | grep -o '"name":"[^"]*"' | cut -d':' -f2- | tr -d '"')
            
            echo "Debug - Found file: $name, modified: $modified" >&2
            
            # Convert modified time to timestamp for comparison
            # Handling ISO-8601 format with timezone (e.g., 2024-05-17T13:47:55.4174917+08:00)
            local timestamp=$(date -d "${modified%+*}" +%s 2>/dev/null)
            
            if [ -z "$timestamp" ]; then
                # Fallback if date conversion fails
                echo "Debug - Failed to parse date: $modified, using string comparison" >&2
                # Use string comparison as fallback
                if [ -z "$latest_time" ] || [[ "$modified" > "$latest_time" ]]; then
                    latest_time="$modified"
                    latest_file="$entry"
                fi
            else
                # Update latest file if this one is newer
                if [ -z "$latest_time" ] || [ $timestamp -gt $latest_time ]; then
                    latest_time=$timestamp
                    latest_file="$entry"
                fi
            fi
        fi
    done
    
    if [ -z "$latest_file" ]; then
        echo "No valid files found" >&2
        return 1
    fi
    
    echo "Debug - Latest file: $latest_file" >&2
    echo "$latest_file"
    return 0
}

# Function to download file from Alist
download_file() {
    local file_path="$1"
    
    echo "Downloading file: $file_path" >&2
    
    local download_data="{\"path\":\"$file_path\",\"password\":\"\"}"
    local response=$(curl -s -X POST "$ALIST_SERVER/api/fs/get" \
        -H "Content-Type: application/json" \
        -H "Authorization: $ALIST_TOKEN" \
        -d "$download_data")
    
    echo "Debug - Get file response: $response" >&2
    
    # Check if successful
    if ! echo "$response" | grep -q '"code":200'; then
        echo "Failed to get download info" >&2
        echo "Response: $response" >&2
        return 1
    fi
    
    # Extract download URL
    local download_url=$(echo "$response" | grep -o '"raw_url":"[^"]*"' | cut -d':' -f2- | tr -d '"')
    
    if [ -z "$download_url" ]; then
        echo "No download URL found" >&2
        return 1
    fi
    
    # Download the file
    local temp_file=$(mktemp)
    curl -s -o "$temp_file" "$download_url"
    
    if [ $? -ne 0 ] || [ ! -s "$temp_file" ]; then
        echo "Failed to download file" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    # Detect file type based on mime-type, file extension, and content analysis
    local mime_type=$(file --mime-type -b "$temp_file")
    local file_extension="${file_path##*.}"
    local file_name="${file_path##*/}"
    
    echo "Debug - Detected MIME type: $mime_type" >&2
    echo "Debug - File extension: $file_extension" >&2
    echo "Debug - File name: $file_name" >&2
    
    # Check for PNG magic bytes
    local header_hex=$(hexdump -n 4 -e '4/1 "%02x"' "$temp_file" 2>/dev/null)
    echo "Debug - File header: $header_hex" >&2
    
    # Determine if this is a text or binary file
    if [[ "$mime_type" == "text/"* ]] && [[ "$header_hex" != "89504e47"* ]] && [ "$file_extension" = "txt" ]; then
        # Text file
        echo "Debug - Handling as text file" >&2
        local content=$(cat "$temp_file")
        rm -f "$temp_file"
        echo "text:$content"
        return 0
    elif [[ "$mime_type" == "image/"* ]] || [[ "$header_hex" == "89504e47"* ]] || [[ "$file_name" == *"image"* ]]; then
        # Image file - ensure correct extension for PNG files
        echo "Debug - Handling as image file" >&2
        
        if [[ "$header_hex" == "89504e47"* ]] && [[ "$file_extension" != "png" ]]; then
            # File has PNG header but wrong extension, rename
            local png_file="${temp_file}.png"
            mv "$temp_file" "$png_file"
            echo "Debug - Renamed to PNG file: $png_file" >&2
            echo "binary:$png_file"
        else
            echo "binary:$temp_file"
        fi
        return 0
    else
        # Other binary file
        echo "Debug - Handling as generic binary file" >&2
        echo "binary:$temp_file"
        return 0
    fi
}

# Main function
main() {
    # Login to Alist
    alist_login
    if [ $? -ne 0 ]; then
        echo "Failed to login to Alist" >&2
        exit 1
    fi
    
    # Get latest file in clipboard directory
    echo "Getting latest file from Alist..." >&2
    latest_file=$(get_latest_file "$ALIST_CLIPBOARD_DIR")
    
    if [ $? -ne 0 ] || [ -z "$latest_file" ]; then
        echo "No files found in Alist clipboard directory" >&2
        exit 1
    fi
    
    # Extract file name
    file_name=$(echo "$latest_file" | grep -o '"name":"[^"]*"' | cut -d':' -f2- | tr -d '"')
    
    if [ -z "$file_name" ]; then
        echo "Error: Could not extract file name from response" >&2
        exit 1
    fi
    
    # Construct full path
    file_path="$ALIST_CLIPBOARD_DIR/$file_name"
    
    echo "Found latest file: $file_name" >&2
    echo "Full path: $file_path" >&2
    
    # Download the file
    download_result=$(download_file "$file_path")
    
    if [ $? -ne 0 ] || [ -z "$download_result" ]; then
        echo "Failed to download file" >&2
        exit 1
    fi
    
    # Parse download result (format: type:content)
    content_type=${download_result%%:*}
    content=${download_result#*:}
    
    # Set clipboard content
    echo "Setting clipboard content..." >&2
    
    if [ "$content_type" = "text" ]; then
        echo "Setting text content to clipboard" >&2
        set_clipboard_content "$content" false ""
    else
        # For binary, content is actually the path to temp file
        echo "Setting binary content to clipboard (file: $content)" >&2
        
        # Check if file exists and has content
        if [ ! -f "$content" ]; then
            echo "Error: Binary file not found: $content" >&2
            exit 1
        fi
        
        if [ ! -s "$content" ]; then
            echo "Error: Binary file is empty: $content" >&2
            exit 1
        fi
        
        set_clipboard_content "" true "$content"
    fi
    
    if [ $? -eq 0 ]; then
        echo "Successfully set clipboard content from Alist" >&2
        exit 0
    else
        echo "Failed to set clipboard content" >&2
        exit 1
    fi
}

# Run the main function
main
