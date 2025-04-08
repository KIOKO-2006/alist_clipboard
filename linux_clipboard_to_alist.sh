#!/bin/bash
# Script to upload clipboard content to Alist server
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
TIME_FORMAT=${TIME_FORMAT:-"%Y%m%d_%H%M%S"}

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

# Function to get clipboard from Wayland
get_wayland_clipboard() {
    if ! command -v wl-paste &> /dev/null; then
        echo "Error: wl-clipboard is not installed. Install with: sudo pacman -S wl-clipboard" >&2
        return 1
    fi
    
    # Check if we have image data
    local mime_type=$(wl-paste -l 2>/dev/null | grep -o 'image/[a-z]*' | head -1)
    if [ -n "$mime_type" ]; then
        echo "Image data detected in clipboard, saving as PNG..." >&2
        
        # Create a temporary file
        local temp_file=$(mktemp)
        wl-paste --no-newline > "$temp_file" 2>/dev/null
        
        if [ -s "$temp_file" ]; then
            echo "$temp_file"
            return 2  # Return code 2 indicates binary data in temp file
        else
            rm -f "$temp_file"
            echo "Failed to get image data from clipboard" >&2
            return 1
        fi
    fi

    # Try to get text
    local content=$(wl-paste -n 2>/dev/null)
    if [ -n "$content" ]; then
        echo "$content"
        return 0
    fi
    
    
    echo "No content found in clipboard" >&2
    return 1
}

# Function to get clipboard from X11
get_x11_clipboard() {
    if ! command -v xclip &> /dev/null; then
        echo "Error: xclip is not installed. Install with: sudo pacman -S xclip" >&2
        return 1
    fi
    
    # Try to get text
    local content=$(xclip -selection clipboard -o 2>/dev/null)
    if [ -n "$content" ]; then
        echo "$content"
        return 0
    fi
    
    # Check if we have image data
    if xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -q 'image/png'; then
        echo "Image data detected in clipboard, saving as PNG..." >&2
        
        # Create a temporary file
        local temp_file=$(mktemp)
        xclip -selection clipboard -t image/png -o > "$temp_file" 2>/dev/null
        
        if [ -s "$temp_file" ]; then
            echo "$temp_file"
            return 2  # Return code 2 indicates binary data in temp file
        else
            rm -f "$temp_file"
            echo "Failed to get image data from clipboard" >&2
            return 1
        fi
    fi
    
    echo "No content found in clipboard" >&2
    return 1
}

# Function to get clipboard content
get_clipboard_content() {
    local display_server=$(detect_display_server)
    
    if [ "$display_server" = "wayland" ]; then
        echo "Detected Wayland display server" >&2
        get_wayland_clipboard
    elif [ "$display_server" = "x11" ]; then
        echo "Detected X11 display server" >&2
        get_x11_clipboard
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
    
    # Print response for debugging
    echo "Debug - Login response: $response" >&2
    
    # Extract token from response using grep and cut
    ALIST_TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d':' -f2 | tr -d '"')
    
    if [ -n "$ALIST_TOKEN" ]; then
        echo "Successfully logged in to Alist server" >&2
        echo "Debug - Token: $ALIST_TOKEN" >&2
        return 0
    else
        echo "Failed to login to Alist server" >&2
        return 1
    fi
}

# Function to create directory on Alist
create_directory() {
    local path="$1"
    
    echo "Creating directory: $path" >&2
    
    local dir_data="{\"path\":\"$path\"}"
    local response=$(curl -s -X POST "$ALIST_SERVER/api/fs/mkdir" \
        -H "Content-Type: application/json" \
        -H "Authorization: $ALIST_TOKEN" \
        -d "$dir_data")
    
    # Check if successful or already exists
    if echo "$response" | grep -q '"code":200'; then
        echo "Directory created successfully" >&2
        return 0
    elif echo "$response" | grep -q 'already exists'; then
        echo "Directory already exists" >&2
        return 0
    else
        echo "Failed to create directory: $path" >&2
        echo "Response: $response" >&2
        return 1
    fi
}

# Function to upload file to Alist
upload_file() {
    local content="$1"
    local is_binary=$2
    local filename="$3"
    
    # Generate filename if not provided
    if [ -z "$filename" ]; then
        local timestamp=$(date +"$TIME_FORMAT")
        if [ "$is_binary" = true ]; then
            filename="clipboard_image_${timestamp}.png"
        else
            filename="clipboard_${timestamp}.txt"
        fi
    fi
    
    # Create clipboard directory if it doesn't exist
    create_directory "$ALIST_CLIPBOARD_DIR"
    
    # Full path in Alist
    local path="$ALIST_CLIPBOARD_DIR/$filename"
    
    echo "Uploading to Alist: $path" >&2
    echo "Debug - Using token: $ALIST_TOKEN" >&2
    
    if [ "$is_binary" = true ]; then
        # For binary data, use the temp file
        local file_size=$(wc -c < "$content")

        upload_url="$ALIST_SERVER/api/fs/put"
        
        # Upload the file using the correct format
        echo "Debug - Uploading directly to Alist at: $ALIST_SERVER/api/fs/put" >&2
        local content_length=$(wc -c < "$content")
        local response=$(curl -v -X PUT "$ALIST_SERVER/api/fs/put" \
            -H "Authorization: $ALIST_TOKEN" \
            -H "File-Path: $path" \
            -H "As-Task: true" \
            -H "Content-Length: $content_length" \
            -H "Content-Type: application/octet-stream" \
            --data-binary @"$content")
        echo "Debug - Server response: $response" >&2
        
        # Clean up temporary file
        rm -f "$content"
        
    else
        # For text data, create a temporary file
        local temp_file=$(mktemp)
        echo "$content" > "$temp_file"
        local file_size=$(wc -c < "$temp_file")
        
        # Upload the file using the correct format
        echo "Debug - Uploading directly to Alist at: $ALIST_SERVER/api/fs/put" >&2
        local content_length=$(wc -c < "$temp_file")
        local response=$(curl -v -X PUT "$ALIST_SERVER/api/fs/put" \
            -H "Authorization: $ALIST_TOKEN" \
            -H "File-Path: $path" \
            -H "As-Task: true" \
            -H "Content-Length: $content_length" \
            -H "Content-Type: application/octet-stream" \
            --data-binary @"$temp_file")
        echo "Debug - Server response: $response" >&2
        
        # Clean up temporary file
        rm -f "$temp_file"
    fi
    
    echo "Successfully uploaded to $path" >&2
    return 0
}

# Main function
main() {
    echo "Getting clipboard content..." >&2
    content=$(get_clipboard_content)
    get_result=$?
    
    if [ $get_result -ne 0 ] && [ $get_result -ne 2 ]; then
        echo "Failed to get clipboard content" >&2
        exit 1
    fi
    
    # Login to Alist
    alist_login
    if [ $? -ne 0 ]; then
        echo "Failed to login to Alist" >&2
        exit 1
    fi
    
    # Upload content
    if [ $get_result -eq 2 ]; then
        # Binary data
        echo "Uploading binary data from clipboard..." >&2
        upload_file "$content" true
    else
        # 检查文本内容开头是否为PNG文件头
        if [[ $(hexdump -n 4 -e '4/1 "%02x"' <<< "$content") == "89504e47"* ]]; then
            echo "Detected PNG image data in clipboard text, handling as image..." >&2
            # 创建临时文件，以正确扩展名保存
            temp_png=$(mktemp -u).png
            echo -n "$content" > "$temp_png"
            upload_file "$temp_png" true
        else
            # 普通文本数据
            content_preview=$(echo "$content" | head -c 50)
            if [ ${#content} -gt 50 ]; then
                content_preview="${content_preview}..."
            fi
            echo "Found text: \"${content_preview}\"" >&2
            upload_file "$content" false
        fi
    fi
    
    if [ $? -eq 0 ]; then
        echo "Successfully uploaded clipboard content to Alist" >&2
        exit 0
    else
        echo "Failed to upload clipboard content" >&2
        exit 1
    fi
}

# Run the main function
main
