/*
 * soloist-audiores 2.0.0
 *
 * Lance Spotify Soloist et le fait se comporter comme un lecteur Sailfish
 * vis-à-vis des autres applications audio (Audiobook, SailCast...) :
 *
 *  - quand Soloist se met à jouer, le lanceur réserve la ressource
 *    « lecture audio » de la classe « player » auprès du gestionnaire de
 *    ressources de Sailfish. Le lecteur qui jouait jusque-là perd cette
 *    ressource et se met en pause, comme lorsque deux applications Sailfish
 *    se relaient ;
 *  - quand Soloist est en pause ou arrêté, la ressource est rendue ;
 *  - quand une autre application prend la ressource (ou un appel
 *    téléphonique), le lanceur met Soloist en pause.
 *
 * L'état de lecture de Soloist vient de son interface locale (« soloist ctl
 * trace », qui suppose que Soloist est lancé avec --ws). La réservation
 * rattache aussi le flux sonore de Soloist au lecteur, ce qui fait agir les
 * boutons de volume sur la musique.
 *
 * Usage : soloist-audiores /chemin/vers/soloist [options de soloist...]
 *         (ajouter --ws 127.0.0.1:0 aux options de Soloist)
 *
 * Compilation sur le téléphone :
 *   gcc -O2 -o soloist-audiores soloist-audiores.c \
 *       $(pkg-config --cflags --libs libresource-glib glib-2.0)
 */
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
static const char     *soloist_path;

static gboolean granted;      /* la ressource est à nous */
static gboolean wanted;       /* Soloist joue : on veut la ressource */
static gboolean pause_sent;   /* pause déjà demandée pour cette perte */

static GPid     trace_pid;
static guint    trace_watch;
static guint    trace_retry;

static void logmsg(const char *msg)
{
    fprintf(stderr, "soloist-audiores: %s\n", msg);
}

/* --- Commandes envoyées à Soloist ------------------------------------- */

static void soloist_ctl(const char *command)
{
    gchar *argv[] = { (gchar *)soloist_path, "ctl", (gchar *)command, NULL };
    GError *error = NULL;
    if (!g_spawn_async(NULL, argv, NULL, G_SPAWN_STDOUT_TO_DEV_NULL
                       | G_SPAWN_STDERR_TO_DEV_NULL, NULL, NULL, NULL, &error)) {
        fprintf(stderr, "soloist-audiores: soloist ctl %s : %s\n", command, error->message);
        g_error_free(error);
    }
}

/* --- Ressource audio ---------------------------------------------------- */

static void grant_cb(resource_set_t *rs, uint32_t resources, void *data)
{
    (void)rs; (void)data;
    gboolean now = (resources & RESOURCE_AUDIO_PLAYBACK) != 0;
    if (now == granted)
        return;
    granted = now;
    if (granted) {
        logmsg("ressource audio obtenue");
        pause_sent = FALSE;
    } else {
        logmsg("ressource audio perdue");
        /* une autre application (ou un appel) joue : Soloist se tait */
        if (wanted && !pause_sent) {
            logmsg("pause de Soloist");
            pause_sent = TRUE;
            soloist_ctl("pause");
        }
    }
}

static void set_playing(gboolean playing)
{
    if (playing == wanted || rset == NULL)
        return;
    wanted = playing;
    if (playing) {
        logmsg("Soloist joue : réservation de la ressource");
        pause_sent = FALSE;
        resource_set_acquire(rset);
    } else {
        logmsg("Soloist en pause : ressource rendue");
        resource_set_release(rset);
        granted = FALSE;
    }
}

/* --- Suivi de l'état de lecture (soloist ctl trace) -------------------- */

/* Valeur du champ "status" d'un événement JSON, ou NULL. */
static gchar *json_status(const gchar *line)
{
    const gchar *p = strstr(line, "\"status\"");
    if (!p)
        return NULL;
    p += strlen("\"status\"");
    while (*p == ' ' || *p == ':' || *p == '\t')
        p++;
    if (*p != '"')
        return NULL;
    p++;
    const gchar *end = strchr(p, '"');
    return end ? g_strndup(p, end - p) : NULL;
}

static void handle_event(const gchar *line)
{
    if (!strstr(line, "\"playback_state\"") && !strstr(line, "\"playback_changed\""))
        return;
    gchar *status = json_status(line);
    if (!status)
        return;
    /* idle, playing, paused, buffering */
    set_playing(g_strcmp0(status, "playing") == 0 || g_strcmp0(status, "buffering") == 0);
    g_free(status);
}

static void start_trace(void);

static gboolean retry_trace(gpointer data)
{
    (void)data;
    trace_retry = 0;
    start_trace();
    return G_SOURCE_REMOVE;
}

static void schedule_trace_retry(void)
{
    if (!trace_retry && child > 0)
        trace_retry = g_timeout_add_seconds(3, retry_trace, NULL);
}

static gboolean trace_readable(GIOChannel *channel, GIOCondition cond, gpointer data)
{
    (void)data;
    gchar *line = NULL;
    gsize length = 0;
    GIOStatus status = G_IO_STATUS_NORMAL;

    if (cond & G_IO_IN) {
        while ((status = g_io_channel_read_line(channel, &line, &length, NULL, NULL))
               == G_IO_STATUS_NORMAL) {
            if (line) {
                handle_event(line);
                g_free(line);
                line = NULL;
            }
        }
    }
    if (status == G_IO_STATUS_EOF || status == G_IO_STATUS_ERROR
        || (cond & (G_IO_HUP | G_IO_ERR))) {
        g_io_channel_shutdown(channel, FALSE, NULL);
        g_io_channel_unref(channel);
        trace_watch = 0;
        schedule_trace_retry();
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}

static void trace_exited(GPid pid, gint status, gpointer data)
{
    (void)status; (void)data;
    g_spawn_close_pid(pid);
    if (pid == trace_pid)
        trace_pid = 0;
}

static void start_trace(void)
{
    gchar *argv[] = { (gchar *)soloist_path, "ctl", "trace", NULL };
    gint out = -1;
    GError *error = NULL;

    if (trace_pid || child <= 0)
        return;
    if (!g_spawn_async_with_pipes(NULL, argv, NULL,
                                  G_SPAWN_DO_NOT_REAP_CHILD | G_SPAWN_STDERR_TO_DEV_NULL,
                                  NULL, NULL, &trace_pid, NULL, &out, NULL, &error)) {
        fprintf(stderr, "soloist-audiores: soloist ctl trace : %s\n", error->message);
        g_error_free(error);
        trace_pid = 0;
        schedule_trace_retry();
        return;
    }
    g_child_watch_add(trace_pid, trace_exited, NULL);
    GIOChannel *channel = g_io_channel_unix_new(out);
    g_io_channel_set_close_on_unref(channel, TRUE);
    g_io_channel_set_flags(channel, G_IO_FLAG_NONBLOCK, NULL);
    trace_watch = g_io_add_watch(channel, G_IO_IN | G_IO_HUP | G_IO_ERR, trace_readable, NULL);
}

/* --- Soloist lui-même --------------------------------------------------- */

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
        fprintf(stderr, "usage : %s soloist [options de soloist...]\n", argv[0]);
        return 2;
    }
    soloist_path = argv[1];

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

    rset = resource_set_create("player", RESOURCE_AUDIO_PLAYBACK, 0, 0, grant_cb, NULL);
    if (rset == NULL)
        logmsg("gestionnaire de ressources injoignable");
    else
        /* rattache les flux sonores du processus Soloist à cette ressource */
        resource_set_configure_audio(rset, "player", child, "*");

    /* laisse à Soloist le temps d'ouvrir son interface locale */
    trace_retry = g_timeout_add_seconds(3, retry_trace, NULL);

    g_main_loop_run(loop);

    if (trace_pid)
        kill(trace_pid, SIGTERM);
    if (rset) {
        resource_set_release(rset);
        resource_set_destroy(rset);
    }
    return child_status;
}
