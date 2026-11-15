/*
 * libforcerole 1.2.0
 *
 * Bibliothèque chargée avant Soloist (LD_PRELOAD). Elle remplace le rôle
 * « music » que Soloist donne à son flux sonore par le rôle « x-maemo »,
 * celui des applications natives de Sailfish OS. Les boutons de volume du
 * téléphone n'agissent que sur les flux qui portent ce rôle.
 *
 * Soloist ne se lie pas directement à libpulse : il la charge à la volée
 * (dlopen) et va chercher ses fonctions avec dlsym. On intercepte donc aussi
 * dlsym pour lui donner nos versions des deux fonctions concernées.
 *
 * Le rôle voulu peut être changé avec la variable FORCE_MEDIA_ROLE.
 * FORCE_MEDIA_ROLE_DEBUG=1 affiche ce que fait la bibliothèque.
 *
 * Compilation :
 *   gcc -O2 -shared -fPIC -o libforcerole.so forcerole.c -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct pa_proplist pa_proplist;
typedef struct pa_context pa_context;
typedef struct pa_stream pa_stream;
typedef struct pa_sample_spec pa_sample_spec;
typedef struct pa_channel_map pa_channel_map;

typedef int (*proplist_sets_fn)(pa_proplist *, const char *, const char *);
typedef pa_stream *(*stream_new_fn)(pa_context *, const char *, const pa_sample_spec *,
                                     const pa_channel_map *, pa_proplist *);
typedef void *(*dlsym_fn)(void *, const char *);

static proplist_sets_fn real_sets;
static stream_new_fn    real_stream_new;
static dlsym_fn         real_dlsym;

static int debug(void)
{
    const char *d = getenv("FORCE_MEDIA_ROLE_DEBUG");
    return d && *d == '1';
}

static const char *role(void)
{
    const char *r = getenv("FORCE_MEDIA_ROLE");
    return (r && *r) ? r : "x-maemo";
}

static void init_dlsym(void)
{
    if (real_dlsym)
        return;
    /* glibc >= 2.34 range dlsym dans libc (GLIBC_2.34) ; avant, version de
     * base de l'architecture aarch64 (GLIBC_2.17). */
    real_dlsym = (dlsym_fn)dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
    if (!real_dlsym)
        real_dlsym = (dlsym_fn)dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.17");
}

static void *lookup_real(const char *name)
{
    void *f;
    init_dlsym();
    f = real_dlsym(RTLD_NEXT, name);
    if (!f) {
        /* libpulse n'est peut-être pas encore chargée, ou l'a été en local */
        void *h = dlopen("libpulse.so.0", RTLD_NOW | RTLD_NOLOAD);
        if (!h)
            h = dlopen("libpulse.so.0", RTLD_NOW);
        if (h)
            f = real_dlsym(h, name);
    }
    return f;
}

int pa_proplist_sets(pa_proplist *p, const char *key, const char *value)
{
    if (!real_sets)
        real_sets = (proplist_sets_fn)lookup_real("pa_proplist_sets");
    if (key && strcmp(key, "media.role") == 0) {
        if (debug())
            fprintf(stderr, "forcerole: media.role %s -> %s\n", value ? value : "(null)", role());
        value = role();
    }
    return real_sets ? real_sets(p, key, value) : -1;
}

pa_stream *pa_stream_new_with_proplist(pa_context *c, const char *name,
                                       const pa_sample_spec *ss,
                                       const pa_channel_map *map,
                                       pa_proplist *p)
{
    if (!real_stream_new)
        real_stream_new = (stream_new_fn)lookup_real("pa_stream_new_with_proplist");
    if (p)
        pa_proplist_sets(p, "media.role", role());
    if (debug())
        fprintf(stderr, "forcerole: nouveau flux \"%s\" avec rôle %s\n", name ? name : "", role());
    return real_stream_new ? real_stream_new(c, name, ss, map, p) : NULL;
}

/* Interception de dlsym : si Soloist demande l'une de nos deux fonctions,
 * on lui donne notre version, qui appellera ensuite la vraie. */
void *dlsym(void *handle, const char *name)
{
    init_dlsym();
    if (name) {
        if (strcmp(name, "pa_proplist_sets") == 0) {
            if (!real_sets)
                real_sets = (proplist_sets_fn)real_dlsym(handle, name);
            return (void *)pa_proplist_sets;
        }
        if (strcmp(name, "pa_stream_new_with_proplist") == 0) {
            if (!real_stream_new)
                real_stream_new = (stream_new_fn)real_dlsym(handle, name);
            return (void *)pa_stream_new_with_proplist;
        }
    }
    return real_dlsym(handle, name);
}
