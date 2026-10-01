// libcivdisplay.dylib
//
// Forces Sid Meier's Civilization V (Aspyr macOS build) to treat a chosen
// display as the "main" display, WITHOUT moving the macOS menu bar.
//
// The game pins its window to the display that CoreGraphics reports as main
// (the one with the menu bar). It imports CGDisplayIsMain() and
// CGMainDisplayID(), so we interpose those and answer for a display of our
// choosing.
//
// Target display is selected with the environment variable CIV5_DISPLAY:
//   (unset) / "external"  -> first non-built-in active display   [default]
//   "builtin"             -> the built-in display
//   "3" / any integer     -> index into CGGetActiveDisplayList (0-based)
//   "IPS225" / any text   -> first display whose product name contains it
//
// Inject with DYLD_INSERT_LIBRARIES. It only rewrites behaviour inside the
// Civilization V process (matched by executable path); other processes get the
// real values.

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int is_civ(void)
{
    static int cached = -1;
    if (cached >= 0) return cached;
    char path[4096];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) { cached = 0; return cached; }
    cached = (strstr(path, "Civilization V") != NULL);
    return cached;
}

// Human readable product name of a display ("IPS225", "Color LCD", ...).
static void display_name(CGDirectDisplayID id, char *out, size_t outlen)
{
    out[0] = 0;
    io_service_t port = CGDisplayIOServicePort(id);
    if (!port) return;
    CFDictionaryRef info = IODisplayCreateInfoDictionary(port, kIODisplayOnlyPreferredName);
    if (!info) return;
    CFDictionaryRef names =
        (CFDictionaryRef)CFDictionaryGetValue(info, CFSTR(kDisplayProductName));
    if (names && CFGetTypeID(names) == CFDictionaryGetTypeID() && CFDictionaryGetCount(names) > 0) {
        const void *key = NULL, *val = NULL;
        CFDictionaryGetKeysAndValues(names, &key, &val);
        CFStringRef s = (CFStringRef)val;
        if (s && CFGetTypeID(s) == CFStringGetTypeID())
            CFStringGetCString(s, out, outlen, kCFStringEncodingUTF8);
    }
    CFRelease(info);
}

// The real main display = the one whose global origin is (0,0).
static CGDirectDisplayID real_main(void)
{
    CGDirectDisplayID ids[32];
    uint32_t n = 0;
    if (CGGetActiveDisplayList(32, ids, &n) != kCGErrorSuccess || n == 0)
        return kCGNullDirectDisplay;
    for (uint32_t i = 0; i < n; i++) {
        CGRect b = CGDisplayBounds(ids[i]);
        if (b.origin.x == 0 && b.origin.y == 0) return ids[i];
    }
    return ids[0];
}

static CGDirectDisplayID first_of(int want_builtin, CGDirectDisplayID *ids, uint32_t n)
{
    for (uint32_t i = 0; i < n; i++)
        if (CGDisplayIsBuiltin(ids[i]) == want_builtin) return ids[i];
    return kCGNullDirectDisplay;
}

static CGDirectDisplayID resolve_target(void)
{
    CGDirectDisplayID ids[32];
    uint32_t n = 0;
    if (CGGetActiveDisplayList(32, ids, &n) != kCGErrorSuccess || n == 0)
        return kCGNullDirectDisplay;

    const char *spec = getenv("CIV5_DISPLAY");
    if (!spec || !*spec || strcasecmp(spec, "external") == 0) {
        CGDirectDisplayID d = first_of(0, ids, n);
        return d != kCGNullDirectDisplay ? d : ids[0];
    }
    if (strcasecmp(spec, "builtin") == 0) {
        CGDirectDisplayID d = first_of(1, ids, n);
        return d != kCGNullDirectDisplay ? d : ids[0];
    }
    char *end = NULL;
    long idx = strtol(spec, &end, 10);
    if (end && *end == '\0') {
        if (idx >= 0 && (uint32_t)idx < n) return ids[idx];
        CGDirectDisplayID d = first_of(0, ids, n);
        return d != kCGNullDirectDisplay ? d : ids[0];
    }
    for (uint32_t i = 0; i < n; i++) {
        char name[256];
        display_name(ids[i], name, sizeof(name));
        if (name[0] && strcasestr(name, spec)) return ids[i];
    }
    CGDirectDisplayID d = first_of(0, ids, n);
    return d != kCGNullDirectDisplay ? d : ids[0];
}

// Cached target; re-resolved when the cached display is no longer active
// (e.g. a monitor was unplugged or the lid was closed/opened).
static CGDirectDisplayID target_main(void)
{
    static CGDirectDisplayID cached = kCGNullDirectDisplay;
    CGDirectDisplayID ids[32];
    uint32_t n = 0;
    if (CGGetActiveDisplayList(32, ids, &n) == kCGErrorSuccess && n > 0) {
        if (cached != kCGNullDirectDisplay) {
            for (uint32_t i = 0; i < n; i++)
                if (ids[i] == cached) return cached;
        }
    }
    cached = resolve_target();
    return cached;
}

static boolean_t my_CGDisplayIsMain(CGDirectDisplayID display)
{
    CGDirectDisplayID m = is_civ() ? target_main() : real_main();
    return (m != kCGNullDirectDisplay && display == m) ? 1 : 0;
}

static CGDirectDisplayID my_CGMainDisplayID(void)
{
    return is_civ() ? target_main() : real_main();
}

#define DYLD_INTERPOSE(repl, orig)                                            \
    __attribute__((used)) static struct {                                     \
        const void *replacement;                                              \
        const void *replacee;                                                 \
    } _interpose_##orig __attribute__((section("__DATA,__interpose"))) = {    \
        (const void *)(uintptr_t)&repl, (const void *)(uintptr_t)&orig        \
    }

DYLD_INTERPOSE(my_CGDisplayIsMain, CGDisplayIsMain);
DYLD_INTERPOSE(my_CGMainDisplayID, CGMainDisplayID);
