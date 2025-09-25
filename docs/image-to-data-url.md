# image-to-data-url.sh

Converts an image file to a base64-encoded data URL, automatically detecting the MIME type.

## Usage
```bash
./image-to-data-url.sh <path_to_image>
```

## Features
- Automatically detects the image's MIME type
- Validates that the image is small enough for practical use as a data URL (32KB max)
- Works on both Linux and macOS
- Validates dependencies before execution
- Provides clear error messages

## Example
```bash
./image-to-data-url.sh icon.png
```
Output:
```
data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...
```

## Requirements
- `file` command for MIME type detection
- `stat` command for file size checking
- `base64` command for encoding
- Bash 5.1+

## Implementation Details

This script performs the following steps:
1. Validates that all required dependencies are available
2. Checks that the input file exists and is not empty
3. Verifies that the file size is below the 32KB threshold
4. Determines the MIME type of the image
5. Encodes the image data as base64
6. Outputs a complete data URL in the format `data:<mime-type>;base64,<encoded-data>`

The script is designed to be cross-platform compatible, working on both Linux and macOS environments.