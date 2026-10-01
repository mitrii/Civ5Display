# Build the universal (x86_64 + arm64) display interposer for Civilization V.

# Note: use a dedicated variable; make's built-in CC would win over "CC ?=".
CLANG      ?= xcrun --sdk macosx clang
CFLAGS     ?= -O2 -Wall
FRAMEWORKS  = -framework ApplicationServices -framework IOKit -framework CoreFoundation
ARCHS       = -arch x86_64 -arch arm64

DYLIB = libcivdisplay.dylib
TEST  = Civilization V test

all: $(DYLIB)

$(DYLIB): src/civdisplay.c
	$(CLANG) -dynamiclib $(CFLAGS) -o $@ $< $(FRAMEWORKS) $(ARCHS)

# Quick self-check: prints how the interposer sees each display.
test: $(DYLIB)
	$(CLANG) $(CFLAGS) -o "$(TEST)" src/disptest.c -framework ApplicationServices
	@for spec in "" external builtin 0 1; do \
		echo "--- CIV5_DISPLAY='$$spec' ---"; \
		CIV5_DISPLAY="$$spec" DYLD_INSERT_LIBRARIES="$(CURDIR)/$(DYLIB)" "./$(TEST)"; \
	done

clean:
	rm -f $(DYLIB) "$(TEST)"

.PHONY: all test clean
