# PowerShell script to download latest clipboard content from Alist
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

# Function to set clipboard content with enhanced error handling
function Set-ClipboardContent {
    param (
        $content,
        $contentType,
        $tempFile = $null
    )
    
    Write-Host "Debug - Setting $contentType content to clipboard"
    
    if ($contentType -eq 'text') {
        try {
            Write-Host 'Setting text to clipboard...'
            # Trim null characters that might cause issues
            $cleanContent = $content -replace '\0', ''
            Set-Clipboard -Value $cleanContent
            return $true
        }
        catch {
            Write-Host "Error setting text to clipboard: $_" -ForegroundColor Red
            return $false
        }
    }
    elseif ($contentType -eq 'image') {
        try {
            Write-Host 'Setting image to clipboard...'
            
            # If we already have a temp file with the image, use it directly
            $shouldDeleteTempFile = $false
            if (-not $tempFile -or -not (Test-Path $tempFile)) {
                $tempFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "clipboard_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
                [System.IO.File]::WriteAllBytes($tempFile, $content)
                $shouldDeleteTempFile = $true
                Write-Host "Debug - Created temporary image file: $tempFile"
            }
            
            # Verify it's a valid image by checking PNG header
            $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
            if ($fileBytes.Length -ge 8 -and 
                $fileBytes[0] -eq 0x89 -and $fileBytes[1] -eq 0x50 -and 
                $fileBytes[2] -eq 0x4E -and $fileBytes[3] -eq 0x47) {
                
                Write-Host "Debug - Verified PNG header"
                
                # Load image and set to clipboard
                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing
                
                $image = [System.Drawing.Image]::FromFile($tempFile)
                [System.Windows.Forms.Clipboard]::SetImage($image)
                
                # Clean up
                $image.Dispose()
                
                if ($shouldDeleteTempFile) {
                    Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
                    Write-Host "Debug - Removed temporary file"
                }
                
                return $true
            }
            else {
                Write-Host "Error: Not a valid PNG image" -ForegroundColor Red
                if ($shouldDeleteTempFile) {
                    Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
                }
                return $false
            }
        }
        catch {
            Write-Host "Error setting image to clipboard: $_" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "Error: Unknown content type: $contentType" -ForegroundColor Red
        return $false
    }
}

# Function to login to Alist API
function Invoke-AlistLogin {
    $alistServer = $env:ALIST_SERVER
    $username = $env:ALIST_USERNAME
    $password = $env:ALIST_PASSWORD
    
    Write-Host 'Logging in to Alist server...'
    
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

# Function to list files in Alist directory
function Get-AlistFiles {
    param (
        [string]$Path
    )
    
    $alistServer = $env:ALIST_SERVER
    $token = $env:ALIST_TOKEN
    
    Write-Host "Listing files in: $Path"
    
    $body = @{
        path = $Path
        password = ""
        page = 1
        per_page = 100
        refresh = $true # Force refresh to get the latest files
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$alistServer/api/fs/list" -Method POST -Body $body -Headers @{
            "Authorization" = $token
            "Content-Type" = "application/json"
        }
        
        Write-Host "Debug - API Response received"
        
        if ($response.code -eq 200) {
            if ($response.data.content -and $response.data.content.Count -gt 0) {
                Write-Host "Found $($response.data.content.Count) files"
                return $response.data.content
            } else {
                Write-Host "No files found in directory" -ForegroundColor Yellow
                return @()
            }
        } else {
            Write-Host "Failed to list files: $($response.message)" -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "Error listing files: $_" -ForegroundColor Red
        return $null
    }
}

# Function to download file from Alist
function Get-AlistFile {
    param (
        [string]$Path
    )
    
    $alistServer = $env:ALIST_SERVER
    $token = $env:ALIST_TOKEN
    
    Write-Host "Downloading file: $Path"
    
    # First get the file info to get the raw_url
    $body = @{
        path = $Path
        password = ""
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$alistServer/api/fs/get" -Method POST -Body $body -Headers @{
            "Authorization" = $token
            "Content-Type" = "application/json"
        }
        
        Write-Host "Debug - File info response received"
        
        if ($response.code -eq 200 -and $response.data.raw_url) {
            $rawUrl = $response.data.raw_url
            Write-Host "Debug - Raw URL: $rawUrl"
            
            # Create a unique temp file with appropriate extension
            $extension = [System.IO.Path]::GetExtension($Path)
            if (-not $extension) {
                # Default to .bin if no extension
                if ($response.data.type -eq 4) { # Text file
                    $extension = ".txt"
                } elseif ($response.data.type -eq 5) { # Image file
                    $extension = ".png"
                } else {
                    $extension = ".bin"
                }
            }
            
            $tempFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "alist_$(Get-Date -Format 'yyyyMMdd_HHmmss')$extension"
            
            # Download the file
            Invoke-WebRequest -Uri $rawUrl -OutFile $tempFile
            
            # Verify the file was downloaded successfully
            if (Test-Path $tempFile) {
                $fileInfo = Get-Item $tempFile
                if ($fileInfo.Length -gt 0) {
                    Write-Host "Downloaded file to: $tempFile (Size: $($fileInfo.Length) bytes)"
                    return $tempFile
                } else {
                    Write-Host "Error: Downloaded file is empty" -ForegroundColor Red
                    Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
                    return $null
                }
            } else {
                Write-Host "Error: Failed to create temp file" -ForegroundColor Red
                return $null
            }
        } else {
            Write-Host "Error: Failed to get file info or raw URL" -ForegroundColor Red
            Write-Host "Response: $($response | ConvertTo-Json -Depth 2)" -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "Error downloading file: $_" -ForegroundColor Red
        return $null
    }
}

# Function to download from Alist directly
function Download-FromAlist {
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
            return @{ Success = $false }
        }
        $token = $env:ALIST_TOKEN
    }
    
    # List files in clipboard directory
    $files = Get-AlistFiles -Path $clipboardDir
    
    if ($null -eq $files) {
        Write-Host "Error retrieving files from Alist" -ForegroundColor Red
        return @{ Success = $false }
    }
    
    if ($files.Count -eq 0) {
        Write-Host "No files found in Alist clipboard directory" -ForegroundColor Yellow
        return @{ Success = $false }
    }
    
    # Sort files by modified time (newest first)
    $latestFile = $files | Sort-Object -Property modified -Descending | Select-Object -First 1
    
    if (-not $latestFile) {
        Write-Host "No valid files found in Alist clipboard directory" -ForegroundColor Yellow
        return @{ Success = $false }
    }
    
    Write-Host "Found latest file: $($latestFile.name) (Modified: $($latestFile.modified))"
    
    # Download the file with retry logic
    $maxRetries = 3
    $retryCount = 0
    $tempFile = $null
    
    while (-not $tempFile -and $retryCount -lt $maxRetries) {
        $tempFile = Get-AlistFile -Path "$clipboardDir/$($latestFile.name)"
        
        if (-not $tempFile) {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "Retry $retryCount of $maxRetries..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    }
    
    if (-not $tempFile) {
        Write-Host "Failed to download file after $maxRetries attempts" -ForegroundColor Red
        return @{ Success = $false }
    }
    
    # Detect content type based on file content, not just extension
    $contentType = "unknown"
    $fileInfo = Get-Item $tempFile
    
    # Check file header for content type detection
    $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
    
    if ($fileBytes.Length -ge 8) {
        # Check for PNG signature
        if ($fileBytes[0] -eq 0x89 -and $fileBytes[1] -eq 0x50 -and $fileBytes[2] -eq 0x4E -and $fileBytes[3] -eq 0x47) {
            Write-Host "Debug - Detected PNG image from file header"
            $contentType = "image"
        }
    }
    
    # If header detection didn't work, use extension and other heuristics
    if ($contentType -eq "unknown") {
        if ($latestFile.name -match "\.txt$") {
            $contentType = "text"
        } elseif ($latestFile.name -match "\.(png|jpg|jpeg|gif|bmp)$") {
            $contentType = "image"
        } elseif ($latestFile.type -eq 4) { # Alist type 4 is text file
            $contentType = "text"
        } elseif ($latestFile.type -eq 5) { # Alist type 5 is image file
            $contentType = "image"
        } else {
            # Try to detect if it's text by checking if it contains only printable ASCII
            $isText = $true
            foreach ($byte in $fileBytes) {
                if (($byte -lt 32 -or $byte -gt 126) -and $byte -ne 10 -and $byte -ne 13 -and $byte -ne 9) {
                    $isText = $false
                    break
                }
            }
            $contentType = if ($isText) { "text" } else { "image" }
        }
    }
    
    Write-Host "Debug - Detected content type: $contentType"
    
    if ($contentType -eq "text") {
        # For text files
        try {
            $content = Get-Content -Path $tempFile -Raw -ErrorAction Stop
            
            # Return with the temp file path so we can clean it up later
            return @{
                Success = $true
                ContentType = "text"
                Content = $content
                TempFile = $tempFile
            }
        }
        catch {
            Write-Host "Error reading text file: $_" -ForegroundColor Red
            Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
            return @{ Success = $false }
        }
    } else {
        # For binary files (images)
        try {
            # For images, we'll keep the temp file and pass it to the clipboard function
            # This avoids unnecessary byte array manipulations
            return @{
                Success = $true
                ContentType = "image"
                TempFile = $tempFile
                # Still include content for backward compatibility
                Content = [System.IO.File]::ReadAllBytes($tempFile)
            }
        }
        catch {
            Write-Host "Error reading binary file: $_" -ForegroundColor Red
            Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
            return @{ Success = $false }
        }
    }
}

# Main logic
Write-Host "Starting Alist clipboard download at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "=================================================="

$downloadResult = Download-FromAlist

if ($downloadResult.Success) {
    $contentType = $downloadResult.ContentType
    $content = $downloadResult.Content
    $tempFile = $downloadResult.TempFile
    
    Write-Host "Downloaded $contentType content successfully"
    
    # Pass the temp file to the clipboard function for more efficient handling
    $success = Set-ClipboardContent -content $content -contentType $contentType -tempFile $tempFile
    
    # Clean up temp file if we still have it and it wasn't handled by Set-ClipboardContent
    if ($tempFile -and (Test-Path $tempFile) -and $contentType -eq "text") {
        Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        Write-Host "Debug - Removed temporary file after setting clipboard"
    }
    
    if ($success) {
        Write-Host "=================================================="
        Write-Host 'Successfully set clipboard content from Alist' -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "=================================================="
        Write-Host 'Failed to set clipboard content' -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "=================================================="
    Write-Host 'Failed to download content from Alist' -ForegroundColor Red
    exit 1
}
