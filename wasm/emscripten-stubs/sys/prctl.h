/* Stub sys/prctl.h for Emscripten.
 *
 * prctl(PR_SET_NAME, ...) is used by libkqueue's posix backend solely to
 * set thread names for debugging.  In WASM there are no named threads, so
 * we provide a no-op stub.
 */
#pragma once

#define PR_SET_NAME 15

#include <stdarg.h>
static inline int prctl(int option, ...) { (void)option; return 0; }
