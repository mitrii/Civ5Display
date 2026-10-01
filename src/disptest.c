// Diagnostic helper: verifies the display interposer without launching the game.
//
// Build it with a name that contains "Civilization V" so the interposer's
// is_civ() check matches, then run it with the dylib injected:
//
//   clang -O2 -o "Civilization V test" src/disptest.c -framework ApplicationServices
//   CIV5_DISPLAY=external DYLD_INSERT_LIBRARIES=./libcivdisplay.dylib "./Civilization V test"
//
// It prints, for every active display, whether the interposed CGDisplayIsMain()
// considers it "main", plus the value of CGMainDisplayID().

#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>

int main(void)
{
    CGDirectDisplayID ids[32];
    uint32_t n = 0;
    CGGetActiveDisplayList(32, ids, &n);
    for (uint32_t i = 0; i < n; i++)
        printf("display[%u] id=%u builtin=%d isMain=%d\n",
               i, ids[i], CGDisplayIsBuiltin(ids[i]), CGDisplayIsMain(ids[i]));
    printf("CGMainDisplayID=%u\n", CGMainDisplayID());
    return 0;
}
