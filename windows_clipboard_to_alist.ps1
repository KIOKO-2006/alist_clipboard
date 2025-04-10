# PowerShell script to upload clipboard content to Alist
# For Windows systems
# Pure PowerShell implementation with minimal dependencies

# Set default values for environment variables
$env:ALIST_SERVER = if ($env:ALIST_SERVER) { $env:ALIST_SERVER } else { "http://localhost:5244" }
$env:ALIST_USERNAME = if ($env:ALIST_USERNAME) { $env:ALIST_USERNAME } else { "admin" }
$env:ALIST_PASSWORD = if ($env:ALIST_PASSWORD) { $env:ALIST_PASSWORD } else { "password" }
$env:ALIST_CLIPBOARD_DIR = if ($env:ALIST_CLIPBOARD_DIR) { $env:ALIST_CLIPBOARD_DIR } else { "/host/clipboard" }
$env:ALIST_TOKEN = if ($env:ALIST_TOKEN) { $env:ALIST_TOKEN } else { "" }

# Load environment variables from .env file if it exists
if (Test-Path .\.env) {
    Write-Host "Loading environment variables from .env file..."
    Get-Content .\.env | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $name = $matches[1]
            $value = $matches[2]
            [Environment]::SetEnvironmentVariable($name, $value, [EnvironmentVariableTarget]::Process)
            Write-Host "Set $name environment variable"
        }
    }
}

# Function to get clipboard content with enhanced content detection
function Get-ClipboardContent {
    Write-Host 'Getting clipboard content...'
    $tempDir = [System.IO.Path]::GetTempPath()
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    
    # Check for text content first
    try {
        $text = Get-Clipboard -TextFormatType Text -Raw -ErrorAction SilentlyContinue
        if ($text) {
            Write-Host 'Text content found in clipboard.'
            
            # Check if text might actually be a PNG in base64 format
            if ($text -match '^iVBORw0KGgo') {
                Write-Host 'Debug - Detected possible base64 encoded PNG in text content'
                try {
                    $tempFile = Join-Path -Path $tempDir -ChildPath "clipboard_${timestamp}.png"
                    $bytes = [Convert]::FromBase64String($text)
                    [System.IO.File]::WriteAllBytes($tempFile, $bytes)
                    
                    # Verify it's a valid PNG by checking magic bytes
                    $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
                    if ($fileBytes.Length -ge 8 -and 
                        $fileBytes[0] -eq 0x89 -and $fileBytes[1] -eq 0x50 -and 
                        $fileBytes[2] -eq 0x4E -and $fileBytes[3] -eq 0x47) {
                        Write-Host 'Debug - Confirmed base64 text is a PNG image'
                        return @{
                            Type = 'image'
                            Content = $fileBytes
                            TempFile = $tempFile
                        }
                    }
                    
                    # Clean up if not a valid PNG
                    Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
                } catch {
                    Write-Host "Debug - Error processing base64 as image: $_"
                    # Continue as text if base64 conversion fails
                }
            }
            
            return @{
                Type = 'text'
                Content = $text
            }
        }
    }
    catch {
        Write-Host "Debug - Error getting text content: $_"
    }
    
    # Check for image content using Windows.Forms.Clipboard (more reliable than System.Drawing)
    try {
        # Using Add-Type to avoid dependencies on external assemblies
        Add-Type -AssemblyName System.Windows.Forms
        
        if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
            Write-Host 'Image content found in clipboard.'
            $tempFile = Join-Path -Path $tempDir -ChildPath "clipboard_${timestamp}.png"
            
            # Get image from clipboard and save as PNG
            $image = [System.Windows.Forms.Clipboard]::GetImage()
            if ($image -ne $null) {
                # Save image to temp file
                try {
                    # Use memory stream to avoid System.Drawing dependency
                    Add-Type -AssemblyName System.Drawing
                    $image.Save($tempFile, [System.Drawing.Imaging.ImageFormat]::Png)
                    
                    # Read file bytes
                    $imageData = [System.IO.File]::ReadAllBytes($tempFile)
                    
                    # Check PNG magic bytes
                    if ($imageData.Length -ge 8 -and 
                        $imageData[0] -eq 0x89 -and $imageData[1] -eq 0x50 -and 
                        $imageData[2] -eq 0x4E -and $imageData[3] -eq 0x47) {
                        Write-Host "Debug - Confirmed PNG image (${tempFile})"
                        return @{
                            Type = 'image'
                            Content = $imageData
                            TempFile = $tempFile
                        }
                    } else {
                        Write-Host "Debug - Image doesn't have PNG header"
                    }
                }
                catch {
                    Write-Host "Debug - Error saving image: $_"
                }
                finally {
                    # Dispose image object
                    if ($image -ne $null) {
                        $image.Dispose()
                    }
                }
            }
        }
    }
    catch {
        Write-Host "Debug - Error processing image content: $_"
    }
    
    Write-Host 'No valid content found in clipboard.' -ForegroundColor Yellow
    return $null
}

# Function to login to Alist API
function Invoke-AlistLogin {
    $alistServer = $env:ALIST_SERVER
    $username = $env:ALIST_USERNAME
    $password = $env:ALIST_PASSWORD
    
    Write-Host "Logging in to Alist server..."
    
    $body = @{
        username = $username
        password = $password
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$alistServer/api/auth/login" -Method POST -Body $body -ContentType "application/json"
        if ($response.code -eq 200) {
            $token = $response.data.token
            [Environment]::SetEnvironmentVariable("ALIST_TOKEN", $token, [EnvironmentVariableTarget]::Process)
            Write-Host "Successfully logged in to Alist server"
            Write-Host "Debug - Token: $token"
            return $true
        } else {
            Write-Host "Failed to login to Alist: $($response.message)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Error logging in to Alist: $_" -ForegroundColor Red
        return $false
    }
}

# Function to create directory in Alist
function New-AlistDirectory {
    param (
        [string]$Path
    )
    
    $alistServer = $env:ALIST_SERVER
    $token = $env:ALIST_TOKEN
    
    Write-Host "Creating directory: $Path"
    
    $body = @{
        path = $Path
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$alistServer/api/fs/mkdir" -Method POST -Body $body -Headers @{
            "Authorization" = $token
            "Content-Type" = "application/json"
        }
        
        if ($response.code -eq 200) {
            Write-Host "Directory created successfully"
            return $true
        } else {
            # Directory might already exist
            Write-Host "Note: $($response.message)"
            return $true
        }
    } catch {
        Write-Host "Error creating directory: $_" -ForegroundColor Red
        return $false
    }
}

# Function to upload to Alist API directly
function Upload-ToAlist {
    param (
        $content, 
        $contentType,
        $existingTempFile = $null
    )
    
    $alistServer = $env:ALIST_SERVER
    $clipboardDir = $env:ALIST_CLIPBOARD_DIR
    $token = $env:ALIST_TOKEN
    
    Write-Host "Debug - Server: $alistServer"
    Write-Host "Debug - Directory: $clipboardDir"
    
    # Login to Alist if no token is available
    if (-not $token) {
        Write-Host "No token available, logging in..."
        $loginSuccess = Invoke-AlistLogin
        if (-not $loginSuccess) {
            Write-Host "Login failed, cannot proceed" -ForegroundColor Red
            return $false
        }
        $token = $env:ALIST_TOKEN
    }
    
    # Create clipboard directory if it doesn't exist
    $dirSuccess = New-AlistDirectory -Path $clipboardDir
    if (-not $dirSuccess) {
        Write-Host "Failed to create or verify directory" -ForegroundColor Red
        return $false
    }
    
    # Create temp file and filename
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $tempFile = $null
    $filename = $null
    $shouldDeleteTempFile = $true
    
    if ($existingTempFile -and (Test-Path $existingTempFile)) {
        # Use existing temp file if provided
        $tempFile = $existingTempFile
        $extension = [System.IO.Path]::GetExtension($tempFile)
        $filename = "clipboard_image_$timestamp$extension"
        $shouldDeleteTempFile = $false # Don't delete the file we didn't create
        Write-Host "Debug - Using existing temp file: $tempFile"
    } elseif ($contentType -eq "text") {
        $filename = "clipboard_$timestamp.txt"
        $tempFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "clipboard_$timestamp.txt"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8
        Write-Host "Debug - Created text temp file: $tempFile"
    } elseif ($contentType -eq "image") {
        $filename = "clipboard_image_$timestamp.png"
        $tempFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "clipboard_$timestamp.png"
        [System.IO.File]::WriteAllBytes($tempFile, $content)
        Write-Host "Debug - Created image temp file: $tempFile"
    }
    
    $path = "$clipboardDir/$filename"
    Write-Host "Uploading to Alist: $path"
    
    # Verify file exists and has content
    if (-not (Test-Path $tempFile)) {
        Write-Host "Error: Temp file not found: $tempFile" -ForegroundColor Red
        return $false
    }
    
    $fileInfo = Get-Item $tempFile
    if ($fileInfo.Length -eq 0) {
        Write-Host "Error: Temp file is empty: $tempFile" -ForegroundColor Red
        if ($shouldDeleteTempFile) {
            Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        }
        return $false
    }
    
    $contentLength = $fileInfo.Length
    Write-Host "Debug - File size: $contentLength bytes"
    
    # Detect file type using first bytes
    $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
    $fileType = "unknown"
    
    if ($fileBytes.Length -ge 4) {
        # Check for PNG signature
        if ($fileBytes[0] -eq 0x89 -and $fileBytes[1] -eq 0x50 -and $fileBytes[2] -eq 0x4E -and $fileBytes[3] -eq 0x47) {
            $fileType = "PNG image"
        }
        # Add more file type detections as needed
    }
    
    Write-Host "Debug - Detected file type: $fileType"
    
    # Upload with retry logic
    $maxRetries = 3
    $retryCount = 0
    $success = $false
    
    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            # Use Invoke-WebRequest for more control over headers
            $headers = @{
                "Authorization" = $token
                "File-Path" = $path
                "As-Task" = "true"
                "Content-Length" = $contentLength
                "Content-Type" = "application/octet-stream"
            }
            
            Write-Host "Debug - Uploading to Alist at: $alistServer/api/fs/put (attempt $($retryCount + 1))"
            $response = Invoke-WebRequest -Uri "$alistServer/api/fs/put" -Method PUT -Headers $headers -InFile $tempFile
            $result = $response.Content | ConvertFrom-Json
            
            Write-Host "Debug - Server response: $($response.Content)"
            
            if ($result.code -eq 200) {
                Write-Host "Successfully uploaded to $path" -ForegroundColor Green
                $success = $true
            } else {
                Write-Host "Upload attempt $($retryCount + 1) failed: $($result.message)" -ForegroundColor Yellow
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Host "Retrying in 2 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                }
            }
        } catch {
            Write-Host "Error on upload attempt $($retryCount + 1): $_" -ForegroundColor Yellow
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "Retrying in 2 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    }
    
    # Clean up temp file if we created it
    if ($shouldDeleteTempFile) {
        Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        Write-Host "Debug - Removed temp file: $tempFile"
    }
    
    return $success
}

# Main logic
Write-Host "Starting Alist clipboard upload at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "================================================="

# Get clipboard content with enhanced detection
$clipboardData = Get-ClipboardContent

if ($clipboardData) {
    $contentType = $clipboardData.Type
    $content = $clipboardData.Content
    $tempFile = $clipboardData.TempFile
    
    if ($contentType -eq 'text') {
        $previewText = if ($content.Length -gt 50) { $content.Substring(0, 50) + '...' } else { $content }
        Write-Host "Found text content (${$content.Length} bytes): `"$previewText`""
    }
    else {
        $sizeKB = [Math]::Round(($content.Length / 1024), 2)
        Write-Host "Found image data ($sizeKB KB)" -ForegroundColor Cyan
        if ($tempFile) {
            Write-Host "Temporary file created at: $tempFile"
        }
    }
    
    # Upload to Alist with the temp file if available
    $success = if ($tempFile) {
        Upload-ToAlist -content $content -contentType $contentType -existingTempFile $tempFile
    } else {
        Upload-ToAlist -content $content -contentType $contentType
    }
    
    if ($success) {
        Write-Host "================================================="
        Write-Host 'Successfully uploaded clipboard content to Alist' -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "================================================="
        Write-Host 'Failed to upload clipboard content' -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "================================================="
    Write-Host 'No content found in clipboard' -ForegroundColor Yellow
    exit 1
}
