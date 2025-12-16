# ARM64 Woz Monitor for Apple M1 Pro

A native ARM64 assembly implementation of the classic Woz Monitor for macOS M1 Pro and later systems. This memory monitor provides a low-level interface to examine and modify a 8GB memory workspace using hexadecimal commands.

## Features

- **64-bit addressing**: Full 64-bit address space support (up to 8GB)
- **Pure ARM64 assembly**: Written entirely in assembly language for maximum performance
- **8GB unified memory workspace**: Utilizes Apple M1 Pro's unified memory architecture
- **Classic Woz Monitor interface**: Familiar command structure for experienced users
- **Dynamic memory allocation**: Uses `mmap` for efficient memory management

## Requirements

- macOS 12.0 or later
- Apple Silicon Mac (M1 Pro or later)
- Xcode Command Line Tools (for `as` and `clang`)

To install Xcode Command Line Tools:
```bash
xcode-select --install
```

## Compilation

### Using Make (Recommended)

Simply run:
```bash
make
```

This will:
1. Assemble `woz.s` into `woz.o`
2. Link `woz.o` to create the `woz` executable

### Manual Compilation

If you prefer to compile manually:

```bash
# Assemble the source file
as -arch arm64 -o woz.o woz.s

# Link the object file
clang -arch arm64 -mmacosx-version-min=12.0 -o woz woz.o
```

### Clean Build Artifacts

To remove compiled files:
```bash
make clean
```

## Usage

### Starting the Monitor

Run the executable:
```bash
./woz
```

You'll see:
```
ARM64 Woz Monitor for Apple M1 Pro (8GB unified memory)
> 
```

### Commands

#### Examine Memory (XAM Mode - Default)

Enter a hexadecimal address to examine memory starting at that location. The monitor displays 8 bytes in hexadecimal format.

**Examples:**
```
> 0
00 00 00 00 00 00 00 00

> 1000
00 00 00 00 00 00 00 00

> FFFFFFFF
00 00 00 00 00 00 00 00
```

**Notes:**
- Addresses can be entered in uppercase or lowercase (automatically converted)
- Addresses support up to 16 hex digits (64-bit addressing)
- Addresses are validated to ensure they're within the 8GB workspace

#### Store Data (STOR Mode)

1. Enter STOR mode by typing `:` at the current XAM address
2. Enter hexadecimal byte pairs to store sequentially

**Example:**
```
> 1000              // Set address to 0x1000 and view
00 00 00 00 00 00 00 00

> :                 // Enter STOR mode at address 0x1000
> DEADBEEF          // Store bytes: DE AD BE EF
> 1000              // Verify what we stored
DE AD BE EF 00 00 00 00
```

#### Block Examine (BLOCKXAM Mode)

Type `.` to enter BLOCKXAM mode:
```
> .
```

#### Run Command

Type `R` to display the current execution address:
```
> R
RUN at 0000000000001000
```

### Complete Example Session

```
$ ./woz
ARM64 Woz Monitor for Apple M1 Pro (8GB unified memory)
> 0
00 00 00 00 00 00 00 00

> 1000
00 00 00 00 00 00 00 00

> :                 // Enter STOR mode at 0x1000
> AABBCCDD          // Store 4 bytes
> 1000              // View stored data
AA BB CC DD 00 00 00 00

> 2000              // Move to new address
00 00 00 00 00 00 00 00

> :                 // Enter STOR mode at 0x2000
> 123456789ABCDEF0  // Store 8 bytes
> 2000              // View stored data
12 34 56 78 9A BC DE F0

> R                 // Show run address
RUN at 0000000000002000
```

### Exiting

Press `Ctrl+C` to exit the monitor.

## Address Space

- **Memory Size**: 8GB (8,589,934,592 bytes)
- **Address Range**: 0x0000000000000000 to 0x00000001FFFFFFFF
- **Address Format**: Up to 16 hexadecimal digits (64-bit)

## Technical Details

- **Architecture**: ARM64 (Apple Silicon)
- **Memory Management**: Dynamic allocation via `mmap` system call
- **Stack Alignment**: 16-byte aligned for macOS compatibility
- **Register Usage**: Follows ARM64 calling conventions (callee-saved registers preserved)

## Limitations

- Memory is allocated at program startup (8GB)
- No persistence - memory is cleared when program exits
- Addresses must be within the 8GB workspace bounds
- Memory is not executable (RUN command only displays address)

## Troubleshooting

### Segmentation Fault

If you encounter a segfault:
1. Ensure you're running on Apple Silicon (not Intel Mac)
2. Check that the memory allocation succeeded (should print welcome message)
3. Verify addresses are within bounds (0 to 8GB)

### Compilation Errors

If compilation fails:
1. Verify Xcode Command Line Tools are installed: `xcode-select -p`
2. Ensure you're using a compatible macOS version (12.0+)
3. Check that you're on an ARM64 system: `uname -m` should show `arm64`

### Memory Allocation Failure

If memory allocation fails:
1. Check available system memory: `sysctl hw.memsize`
2. Ensure you have sufficient available RAM
3. The program will exit with error code 1 if `mmap` fails

## License

This is a reference implementation of the Woz Monitor for educational purposes.

## Credits

Based on the original Woz Monitor by Steve Wozniak. Adapted for ARM64 Apple Silicon by the community.

