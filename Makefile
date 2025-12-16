# Makefile for ARM64 Woz Monitor on macOS (M1 Pro and higher)

CC = clang
ASM = as
CFLAGS = -arch arm64 -mmacosx-version-min=12.0

woz: woz.s
	$(ASM) -arch arm64 -o woz.o woz.s
	$(CC) $(CFLAGS) -o woz woz.o

clean:
	rm -f woz woz.o

.PHONY: clean

