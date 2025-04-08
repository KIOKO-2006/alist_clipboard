# Alist Clipboard Integration

Scripts to integrate your system clipboard with an Alist server.

## Features

- Upload clipboard content to Alist server
- Download latest clipboard content from Alist server to local clipboard
- Support for both Linux (Wayland/X11) and Windows
- Configuration via .env file

## Requirements

### Linux Requirements

- Wayland: `wl-clipboard` package
- X11: `xclip` package
- Basic tools: `curl`, `grep`, `sed`
- No Python required for Linux scripts

### Windows Requirements

- PowerShell 5.0+
- Python 3.6+
- Required Python packages: see requirements.txt

## Setup

1. Copy `.env.example` to `.env`
2. Edit `.env` with your Alist server details
3. For Windows only: Install required packages: `pip install -r requirements.txt`

## Usage

### Linux Usage

Upload clipboard to Alist:

```bash
./linux_clipboard_to_alist.sh
```

Download from Alist to clipboard:

```bash
./linux_alist_to_clipboard.sh
```

### Windows Usage

Upload clipboard to Alist:

```powershell
.\windows_clipboard_to_alist.ps1
```

Download from Alist to clipboard:

```powershell
.\windows_alist_to_clipboard.ps1
```
