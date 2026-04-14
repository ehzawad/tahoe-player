#include <dlfcn.h>
#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>

static inline void *tahoe_mpv_get_proc_address(void *ctx, const char *name) {
    (void)ctx;
    static void *open_gl_library = NULL;
    if (!open_gl_library) {
        open_gl_library = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_LAZY);
    }
    return open_gl_library ? dlsym(open_gl_library, name) : NULL;
}
