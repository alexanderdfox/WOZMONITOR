.section __DATA,__data
.align 4

// Memory and State
// Apple M1 Pro unified memory: typically 16GB or 32GB
// Using 8GB (0x200000000) as monitor workspace
memorySize = 8589934592  // 8 GB (0x200000000)
memory_ptr: .quad 0      // Pointer to dynamically allocated memory

XAM: .quad 0x0000000000000000   // 64-bit examine address
STOR: .quad 0x0000000000000000  // 64-bit store address

// Mode: 0=XAM, 1=STOR, 2=BLOCKXAM
mode: .byte 0

// String constants
prompt: .asciz "> "
welcome_msg: .asciz "ARM64 Woz Monitor for Apple M1 Pro (8GB unified memory)\n"
run_msg_prefix: .asciz "RUN at "
run_msg_suffix: .asciz "\n"
newline: .asciz "\n"
space: .asciz " "

// Hex digits for conversion
hex_digits: .asciz "0123456789ABCDEF"

// Input buffer (256 bytes max)
input_buffer: .space 256, 0
input_length: .word 0

// Temporary storage for parsing
process_index: .word 0

.section __TEXT,__text
.globl _main

.align 2

// macOS system call numbers
.equ SYS_write, 0x2000004
.equ SYS_read, 0x2000003
.equ SYS_exit, 0x2000001
.equ SYS_mmap, 0x20000C5  // mmap syscall on macOS

// Macro to load syscall number into x16
.macro load_syscall_write
    movz x16, #0x0004
    movk x16, #0x2000, lsl #16
.endm

.macro load_syscall_read
    movz x16, #0x0003
    movk x16, #0x2000, lsl #16
.endm

.macro load_syscall_mmap
    movz x16, #0x00C5
    movk x16, #0x2000, lsl #16
.endm

.macro load_syscall_exit
    movz x16, #0x0001
    movk x16, #0x2000, lsl #16
.endm

// Print hex byte (w0 = byte)
print_hex_byte:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    
    mov w1, w0          // save original byte
    lsr w0, w0, #4      // high nibble
    and w0, w0, #0x0F
    
    // Load hex_digits string address
    adrp x2, hex_digits@PAGE
    add x2, x2, hex_digits@PAGEOFF
    
    // Get first hex digit character
    ldrb w3, [x2, x0]
    
    // Store on stack for syscall
    strb w3, [sp, #16]
    
    // Print first digit
    load_syscall_write
    mov x0, #1          // stdout
    mov x1, x29
    add x1, x1, #16     // point to stored byte
    mov x2, #1          // 1 byte
    svc #0
    
    // Get second hex digit
    and w0, w1, #0x0F   // low nibble
    ldrb w3, [x2, x0]
    
    // Store on stack
    strb w3, [sp, #16]
    
    // Print second digit
    load_syscall_write
    mov x0, #1
    mov x1, x29
    add x1, x1, #16
    mov x2, #1
    svc #0
    
    // Print space
    adrp x1, space@PAGE
    add x1, x1, space@PAGEOFF
    load_syscall_write
    mov x0, #1
    mov x2, #1
    svc #0
    
    ldp x29, x30, [sp], #32
    ret

// Print string (x0 = string address)
print_str:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    mov x29, sp
    
    mov x19, x0         // save string address
    mov x20, x0         // for length calculation
    
    // Calculate string length
_strlen_loop:
    ldrb w1, [x20], #1
    cmp w1, #0
    bne _strlen_loop
    sub x2, x20, x19
    sub x2, x2, #1      // length
    
    // Write string
    load_syscall_write
    mov x0, #1          // stdout
    mov x1, x19         // string address
    svc #0
    
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// Print 64-bit hex address (x0 = address)
print_hex_address:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    
    mov x19, x0         // save address
    mov x20, #60        // bit shift (start at bit 60, print 16 nibbles)
    
print_addr_loop:
    cmp x20, #0
    blt print_addr_done
    
    // Extract nibble
    mov x0, x19         // copy address
    lsr x0, x0, x20     // shift right by x20 bits
    and x0, x0, #0x0F   // mask to get nibble
    bl print_hex_nibble
    
    sub x20, x20, #4
    b print_addr_loop

print_addr_done:
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// Print hex nibble (w0 = nibble 0-15)
print_hex_nibble:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    
    // Load hex_digits string address
    adrp x1, hex_digits@PAGE
    add x1, x1, hex_digits@PAGEOFF
    
    // Get hex digit character
    ldrb w2, [x1, w0, sxtw]
    
    // Store on stack for syscall
    strb w2, [sp, #16]
    
    // Print digit
    load_syscall_write
    mov x0, #1          // stdout
    add x1, x29, #16    // point to stored byte
    mov x2, #1          // 1 byte
    svc #0
    
    ldp x29, x30, [sp], #32
    ret

// Parse hex digit (w0 = char) returns digit in w0, 0xFF if invalid
parse_hex_digit:
    // Check '0'-'9'
    cmp w0, #0x30       // '0'
    blo invalid_digit
    cmp w0, #0x39       // '9'
    ble numeric_digit
    
    // Check 'A'-'F'
    cmp w0, #0x41       // 'A'
    blo invalid_digit
    cmp w0, #0x46       // 'F'
    bgt invalid_digit
    sub w0, w0, #0x41
    add w0, w0, #10
    ret

numeric_digit:
    sub w0, w0, #0x30
    ret

invalid_digit:
    mov w0, #0xFF
    ret

// Parse hex byte (index passed via global process_index)
// Returns byte in w0, 0xFF if invalid, updates process_index
parse_hex_byte:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    
    // Load current index
    adrp x19, process_index@PAGE
    add x19, x19, process_index@PAGEOFF
    ldr w20, [x19]      // current index
    
    // Check bounds
    adrp x0, input_length@PAGE
    add x0, x0, input_length@PAGEOFF
    ldr w0, [x0]
    cmp w20, w0
    bge parse_fail
    
    // Get first digit
    adrp x0, input_buffer@PAGE
    add x0, x0, input_buffer@PAGEOFF
    ldrb w0, [x0, w20, sxtw]
    bl parse_hex_digit
    cmp w0, #0xFF
    beq parse_fail
    mov w21, w0         // save high nibble
    
    // Increment index
    add w20, w20, #1
    str w20, [x19]
    
    // Check bounds for second digit
    adrp x0, input_length@PAGE
    add x0, x0, input_length@PAGEOFF
    ldr w0, [x0]
    cmp w20, w0
    bge parse_fail
    
    // Get second digit
    adrp x0, input_buffer@PAGE
    add x0, x0, input_buffer@PAGEOFF
    ldrb w0, [x0, w20, sxtw]
    bl parse_hex_digit
    cmp w0, #0xFF
    beq parse_fail
    
    // Combine nibbles
    lsl w21, w21, #4
    orr w0, w21, w0
    
    // Increment index
    add w20, w20, #1
    str w20, [x19]
    
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

parse_fail:
    mov w0, #0xFF
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// Parse hex address (up to 16 hex digits, updates process_index)
// Returns address in x0, -1 (0xFFFFFFFFFFFFFFFF) if invalid
parse_hex_address:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    
    // Load current index
    adrp x19, process_index@PAGE
    add x19, x19, process_index@PAGEOFF
    ldr w20, [x19]      // current index
    
    // Get input length
    adrp x0, input_length@PAGE
    add x0, x0, input_length@PAGEOFF
    ldr w0, [x0]
    
    // Initialize address to 0
    mov x21, #0         // accumulated address
    mov x22, #0         // digit count
    
parse_addr_loop:
    // Check if we've reached max digits (16) or end of input
    cmp x22, #16
    bge parse_addr_done
    cmp w20, w0
    bge parse_addr_done
    
    // Get next character
    adrp x0, input_buffer@PAGE
    add x0, x0, input_buffer@PAGEOFF
    ldrb w0, [x0, w20, sxtw]
    
    // Try to parse as hex digit
    bl parse_hex_digit
    cmp w0, #0xFF
    beq parse_addr_check  // stop at first non-hex character
    
    // Shift address left 4 bits and add new digit
    lsl x21, x21, #4
    add x21, x21, x0
    
    // Increment index and digit count
    add w20, w20, #1
    str w20, [x19]
    add x22, x22, #1
    b parse_addr_loop

parse_addr_check:
    // If no digits were parsed, return error
    cmp x22, #0
    beq parse_addr_fail

parse_addr_done:
    mov x0, x21         // return address
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

parse_addr_fail:
    // Return error value (-1)
    mov x0, #0xFFFFFFFF
    movk x0, #0xFFFF, lsl #16
    movk x0, #0xFFFF, lsl #32
    movk x0, #0xFFFF, lsl #48
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// XAM Print (x0 = address - 64-bit)
xam_print:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    
    // Validate memory pointer first
    adrp x1, memory_ptr@PAGE
    add x1, x1, memory_ptr@PAGEOFF
    ldr x1, [x1]          // load pointer to memory
    cbz x1, xam_done      // if null, exit
    
    mov x19, x0         // base address (64-bit)
    mov x20, #0         // i = 0 (64-bit)
    
xam_loop:
    cmp x20, #8
    bge xam_done
    
    add x0, x19, x20    // addr = base + i (64-bit)
    // Check bounds (8GB = 0x200000000)
    movz x2, #0x0000
    movk x2, #0x2000, lsl #16
    movk x2, #0x0000, lsl #32
    cmp x0, x2
    bge xam_done
    
    // Load byte from memory (x1 already has memory_ptr)
    ldrb w0, [x1, x0]     // load byte at address
    
    // Print hex byte
    bl print_hex_byte
    
    add x20, x20, #1
    b xam_loop

xam_done:
    // Print newline
    adrp x0, newline@PAGE
    add x0, x0, newline@PAGEOFF
    bl print_str
    
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// Read line (reads into input_buffer, sets input_length)
read_line:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    
    // Print prompt
    adrp x0, prompt@PAGE
    add x0, x0, prompt@PAGEOFF
    bl print_str
    
    // Read from stdin
    adrp x1, input_buffer@PAGE
    add x1, x1, input_buffer@PAGEOFF
    load_syscall_read
    mov x0, #0          // stdin
    mov x2, #256        // max bytes
    svc #0
    
    // Store length (subtract 1 for newline if present)
    cmp x0, #1
    ble read_empty
    
    // Check if last char is newline
    adrp x1, input_buffer@PAGE
    add x1, x1, input_buffer@PAGEOFF
    add x2, x1, x0
    sub x2, x2, #1
    ldrb w3, [x2]
    cmp w3, #0x0A       // '\n'
    sub x0, x0, #1
    bne store_length
    sub x0, x0, #1      // subtract one more for newline

store_length:
    adrp x1, input_length@PAGE
    add x1, x1, input_length@PAGEOFF
    str w0, [x1]
    
    // Convert to uppercase and compact
    adrp x1, input_buffer@PAGE
    add x1, x1, input_buffer@PAGEOFF
    mov x2, x1          // read pointer
    mov x3, x1          // write pointer
    mov w4, w0          // length counter
    
uppercase_loop:
    cmp w4, #0
    ble uppercase_done
    ldrb w5, [x2], #1
    // Check if lowercase
    cmp w5, #0x61       // 'a'
    blo not_lowercase
    cmp w5, #0x7A       // 'z'
    bhi not_lowercase
    sub w5, w5, #32     // convert to uppercase
not_lowercase:
    strb w5, [x3], #1
    sub w4, w4, #1
    b uppercase_loop

uppercase_done:
    // Null terminate
    strb wzr, [x3]
    
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

read_empty:
    adrp x1, input_length@PAGE
    add x1, x1, input_length@PAGEOFF
    str wzr, [x1]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// Process line
process_line:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!  // save x23 for stor_mode
    
    // Initialize index
    adrp x0, process_index@PAGE
    add x0, x0, process_index@PAGEOFF
    str wzr, [x0]
    
process_loop:
    // Check if index < input_length
    ldr w19, [x0]       // current index
    adrp x1, input_length@PAGE
    add x1, x1, input_length@PAGEOFF
    ldr w1, [x1]
    cmp w19, w1
    bge process_done
    
    // Get char
    adrp x2, input_buffer@PAGE
    add x2, x2, input_buffer@PAGEOFF
    ldrb w20, [x2, w19, sxtw]
    
    // Switch on char
    cmp w20, #0x2E      // '.'
    beq dot_case
    cmp w20, #0x3A      // ':'
    beq colon_case
    cmp w20, #0x52      // 'R'
    beq r_case
    
    // Check mode first
    adrp x0, mode@PAGE
    add x0, x0, mode@PAGEOFF
    ldrb w0, [x0]
    
    cmp w0, #1          // STOR
    beq stor_mode
    
    // XAM or BLOCKXAM - try parse hex address
    adrp x0, process_index@PAGE
    add x0, x0, process_index@PAGEOFF
    str w19, [x0]
    bl parse_hex_address
    
    // Check if we got a valid address (not -1/0xFFFFFFFFFFFFFFFF)
    // -1 means error, check by adding 1 and seeing if result is 0
    add x1, x0, #1
    cbz x1, invalid_char  // if x0 was -1, x1 will be 0
    
    // Also check if address is within bounds (8GB = 0x200000000)
    movz x1, #0x0000
    movk x1, #0x2000, lsl #16
    movk x1, #0x0000, lsl #32
    cmp x0, x1
    bge invalid_char     // address out of bounds
    
    // Got a valid address in x0
    mov x22, x0         // save address (64-bit)
    
    // Store address in XAM
    adrp x0, XAM@PAGE
    add x0, x0, XAM@PAGEOFF
    str x22, [x0]
    
    // Print the address location
    mov x0, x22
    bl xam_print
    
    // Load updated index
    adrp x0, process_index@PAGE
    add x0, x0, process_index@PAGEOFF
    ldr w19, [x0]
    b process_loop

stor_mode:
    // Validate memory pointer first
    adrp x0, memory_ptr@PAGE
    add x0, x0, memory_ptr@PAGEOFF
    ldr x23, [x0]        // load pointer to memory (save in x23)
    cbz x23, stor_done   // if null, exit
    
    // Load STOR address (64-bit)
    adrp x0, STOR@PAGE
    add x0, x0, STOR@PAGEOFF
    ldr x22, [x0]        // load current store address
    
    // Parse data bytes to store
    adrp x0, process_index@PAGE
    add x0, x0, process_index@PAGEOFF
    str w19, [x0]
    
stor_byte_loop:
    // Parse next hex byte
    bl parse_hex_byte
    cmp w0, #0xFF
    beq stor_done
    
    // Got a byte in w0, store it
    mov w21, w0
    
    // Check bounds (8GB = 0x200000000)
    movz x1, #0x0000
    movk x1, #0x2000, lsl #16
    movk x1, #0x0000, lsl #32
    cmp x22, x1
    bge stor_done
    
    // Store byte (x23 already has memory_ptr)
    strb w21, [x23, x22]   // store byte at address
    
    // Increment address
    add x22, x22, #1
    
    // Update STOR
    adrp x0, STOR@PAGE
    add x0, x0, STOR@PAGEOFF
    str x22, [x0]
    
    // Get updated index and continue
    adrp x0, process_index@PAGE
    add x0, x0, process_index@PAGEOFF
    ldr w19, [x0]
    b stor_byte_loop

stor_done:
    // Load updated index
    adrp x0, process_index@PAGE
    add x0, x0, process_index@PAGEOFF
    ldr w19, [x0]
    b process_loop

dot_case:
    // mode = BLOCKXAM (2)
    adrp x0, mode@PAGE
    add x0, x0, mode@PAGEOFF
    mov w1, #2
    strb w1, [x0]
    add w19, w19, #1
    adrp x0, process_index@PAGE
    add x0, x0, process_index@PAGEOFF
    str w19, [x0]
    b process_loop

colon_case:
    // mode = STOR (1)
    adrp x0, mode@PAGE
    add x0, x0, mode@PAGEOFF
    mov w1, #1
    strb w1, [x0]
    // STOR = XAM (copy 64-bit address)
    adrp x0, XAM@PAGE
    add x0, x0, XAM@PAGEOFF
    ldr x1, [x0]
    adrp x0, STOR@PAGE
    add x0, x0, STOR@PAGEOFF
    str x1, [x0]
    add w19, w19, #1
    adrp x0, process_index@PAGE
    add x0, x0, process_index@PAGEOFF
    str w19, [x0]
    b process_loop

r_case:
    stp x19, x20, [sp, #-16]!  // save callee-saved registers
    
    // Print RUN message with address
    adrp x0, run_msg_prefix@PAGE
    add x0, x0, run_msg_prefix@PAGEOFF
    bl print_str
    
    // Load 64-bit address from XAM
    adrp x0, XAM@PAGE
    add x0, x0, XAM@PAGEOFF
    ldr x0, [x0]
    
    // Print address as 16 hex digits
    bl print_hex_address
    
    // Print suffix
    adrp x0, run_msg_suffix@PAGE
    add x0, x0, run_msg_suffix@PAGEOFF
    bl print_str

r_case_done:
    ldp x19, x20, [sp], #16
    b process_done

invalid_char:
    add w19, w19, #1
    adrp x0, process_index@PAGE
    add x0, x0, process_index@PAGEOFF
    str w19, [x0]
    b process_loop

process_done:
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_main:
    // Set up stack frame (16-byte aligned)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    
    // Ensure stack is 16-byte aligned for syscalls
    // SP should already be aligned after the stp operations
    
    // Allocate 8GB of memory using mmap (matching M1 Pro unified memory)
    // mmap(addr=0, len=8GB, prot=READ|WRITE, flags=MAP_ANONYMOUS|MAP_PRIVATE, fd=-1, offset=0)
    load_syscall_mmap
    mov x0, #0            // addr (NULL = let kernel choose)
    movz x1, #0x0000      // len low 16 bits (8GB = 0x200000000)
    movk x1, #0x2000, lsl #16  // len middle 16 bits
    movk x1, #0x0000, lsl #32  // len high 16 bits
    mov x2, #0x3          // prot: PROT_READ|PROT_WRITE
    mov x3, #0x1002       // flags: MAP_ANONYMOUS|MAP_PRIVATE
    mov x4, #-1           // fd (-1 for anonymous)
    mov x5, #0            // offset
    svc #0
    
    // Check for error (negative return value)
    cmp x0, #0
    blt mmap_error
    
    // Store pointer to allocated memory
    adrp x1, memory_ptr@PAGE
    add x1, x1, memory_ptr@PAGEOFF
    str x0, [x1]
    
    // Print welcome
    adrp x0, welcome_msg@PAGE
    add x0, x0, welcome_msg@PAGEOFF
    bl print_str

main_loop:
    bl read_line
    
    // Check if empty
    adrp x0, input_length@PAGE
    add x0, x0, input_length@PAGEOFF
    ldr w0, [x0]
    cmp w0, #0
    beq main_loop
    
    bl process_line
    b main_loop

mmap_error:
    // If mmap fails, exit with error code
    load_syscall_exit
    mov x0, #1
    svc #0
    
    // Restore stack (should never reach here, but for completeness)
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
