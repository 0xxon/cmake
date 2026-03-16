/* Stub fts.h for Emscripten.
 *
 * fts (file tree traversal) is used only by zeekygen (the documentation
 * generator) which is never activated in a WASM offline-pcap build.
 * These stubs satisfy the compiler; the functions will never be called.
 */
#pragma once

#include <sys/types.h>
#include <sys/stat.h>
#include <stddef.h>

typedef struct {
    struct stat fts_statp_val;
    char*       fts_path;
    short       fts_info;
    /* minimal padding to avoid size-zero struct warnings */
    int         _pad;
} FTSENT;

typedef struct {
    int _opaque;
} FTS;

/* fts_info flags */
#define FTS_F        8   /* regular file */
#define FTS_D        1   /* directory */
#define FTS_DP       6   /* directory, post-order */
#define FTS_ERR      7   /* error */
#define FTS_NS       11  /* no stat */
#define FTS_NOCHDIR  0x0004

#ifdef __cplusplus
extern "C" {
#endif

static inline FTS* fts_open(char* const* path_argv, int options,
                             int (*compar)(const FTSENT**, const FTSENT**))
    { (void)path_argv; (void)options; (void)compar; return NULL; }

static inline FTSENT* fts_read(FTS* sp)
    { (void)sp; return NULL; }

static inline int fts_close(FTS* sp)
    { (void)sp; return 0; }

#ifdef __cplusplus
}
#endif
