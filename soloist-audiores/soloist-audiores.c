/*
 * soloist-audiores 1.0.0
 *
 * Lance Spotify Soloist (ou tout autre lecteur) et réserve pour lui, auprès
 * du gestionnaire de ressources de Sailfish OS, la ressource « lecture audio »
 * de la classe « player ». Sans cette réservation, le système ne considère
 * pas Soloist comme un lecteur de musique : les boutons de volume règlent
 * alors la sonnerie au lieu du son de la musique.
 *
 * Usage : soloist-audiores /chemin/vers/soloist [options de soloist...]
 *
 * Compilation sur le téléphone :
 *   gcc -O2 -o soloist-audiores soloist-audiores.c \
 *       $(pkg-config --cflags --libs libresource-glib glib-2.0)
 */
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <glib.h>
#include <glib-unix.h>
#include <resource.h>

static GMainLoop      *loop;
static resource_set_t *rset;
static pid_t           child;
static int             child_status = 1;
static gboolean        granted;

static void grant_cb(resource_set_t *rs, uint32_t resources, void *data)
{
    (void)rs; (void)data;
    granted = (resources & RESOURCE_AUDIO_PLAYBACK) != 0;
    fprintf(stderr, "soloist-audiores: ressource audio %s\n",
            granted ? "obtenue" : "perdue (en attente)");
}

/* Le gestionnaire signale que la ressource redevient disponible
 * (par exemple après un appel téléphonique) : on la redemande. */
static void advice_cb(resource_set_t *rs, uint32_t resources, void *data)
{
    (void)data;
    if (!granted && (resources & RESOURCE_AUDIO_PLAYBACK))
        resource_set_acquire(rs);
}

static void child_exited(GPid pid, gint status, gpointer data)
{
    (void)data;
    g_spawn_close_pid(pid);
    child_status = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    child = 0;
    g_main_loop_quit(loop);
}

static gboolean on_signal(gpointer data)
{
    int sig = GPOINTER_TO_INT(data);
    if (child > 0)
        kill(child, sig);          /* Soloist s'arrête, child_exited suit */
    else
        g_main_loop_quit(loop);
    return G_SOURCE_CONTINUE;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage : %s programme [arguments...]\n", argv[0]);
        return 2;
    }

    child = fork();
    if (child < 0) {
        perror("fork");
        return 1;
    }
    if (child == 0) {
        execv(argv[1], &argv[1]);
        perror("execv");
        _exit(127);
    }

    loop = g_main_loop_new(NULL, FALSE);
    g_child_watch_add(child, child_exited, NULL);
    g_unix_signal_add(SIGTERM, on_signal, GINT_TO_POINTER(SIGTERM));
    g_unix_signal_add(SIGINT,  on_signal, GINT_TO_POINTER(SIGINT));

    rset = resource_set_create("player", RESOURCE_AUDIO_PLAYBACK, 0, 0,
                               grant_cb, NULL);
    if (rset == NULL) {
        fprintf(stderr, "soloist-audiores: gestionnaire de ressources injoignable\n");
    } else {
        resource_set_configure_advice_callback(rset, advice_cb, NULL);
        /* rattache tous les flux sonores du processus Soloist */
        resource_set_configure_audio(rset, "player", child, "*");
        resource_set_acquire(rset);
    }

    g_main_loop_run(loop);

    if (rset) {
        resource_set_release(rset);
        resource_set_destroy(rset);
    }
    return child_status;
}
