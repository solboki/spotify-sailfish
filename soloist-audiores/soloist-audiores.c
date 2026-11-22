/*
 * soloist-audiores 2.1.0
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
 * trace », qui suppose que Soloist est lancé avec --ws).
 *
 * Le gestionnaire de ressources ne signale pas toujours la perte de la
 * ressource. Le lanceur surveille donc aussi PulseAudio (« pactl subscribe ») :
 * si un autre lecteur (groupe « player ») se met à jouer pendant que Soloist
 * joue, Soloist est mis en pause.
 *
 * Journal : ~/.cache/soloist-audiores.log La réservation
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
#include <sys/stat.h>
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
static gint64   playing_since; /* début de la lecture (µs, horloge monotone) */

static GPid     trace_pid;
static guint    trace_watch;
static guint    trace_retry;

static FILE *logfile;

static void logmsg(const char *msg)
{
    fprintf(stderr, "soloist-audiores: %s\n", msg);
    if (!logfile) {
        gchar *dir = g_build_filename(g_get_user_cache_dir(), NULL);
        g_mkdir_with_parents(dir, 0700);
        gchar *path = g_build_filename(dir, "soloist-audiores.log", NULL);
        /* repart de zéro au-delà de 200 Ko */
        struct stat st;
        logfile = fopen(path, (stat(path, &st) == 0 && st.st_size > 200000) ? "w" : "a");
        g_free(path);
        g_free(dir);
        if (!logfile)
            return;
    }
    GDateTime *now = g_date_time_new_now_local();
    gchar *stamp = g_date_time_format(now, "%Y-%m-%d %H:%M:%S");
    fprintf(logfile, "%s %s\n", stamp, msg);
    fflush(logfile);
    g_free(stamp);
    g_date_time_unref(now);
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
        playing_since = g_get_monotonic_time();
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

/* --- Surveillance des autres lecteurs (PulseAudio) ---------------------- */

/* environnement du lanceur, en anglais pour lire la sortie de pactl */
static gchar **c_environ(void)
{
    static gchar **env;
    if (!env) {
        env = g_get_environ();
        env = g_environ_setenv(env, "LC_ALL", "C", TRUE);
        env = g_environ_unsetenv(env, "LD_PRELOAD");
    }
    return env;
}

static GHashTable *stream_corked;   /* index du flux -> 1 en pause, 2 joue */
static GPid        pactl_pid;
static guint       pactl_retry;
static guint       check_pending;
static gboolean    snapshot_done;

/* Un autre lecteur se met à jouer pendant que Soloist joue : pause. */
static void other_player_started(const gchar *binary)
{
    gchar *msg = g_strdup_printf("autre lecteur actif (%s) : pause de Soloist", binary);
    logmsg(msg);
    g_free(msg);
    pause_sent = TRUE;
    soloist_ctl("pause");
}

static gboolean check_streams(gpointer data)
{
    (void)data;
    check_pending = 0;
    gchar *argv[] = { "pactl", "list", "sink-inputs", NULL };
    gchar *out = NULL;
    if (!g_spawn_sync(NULL, argv, c_environ(), G_SPAWN_SEARCH_PATH | G_SPAWN_STDERR_TO_DEV_NULL,
                      NULL, NULL, &out, NULL, NULL, NULL) || !out) {
        g_free(out);
        return G_SOURCE_REMOVE;
    }

    GHashTable *seen = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    gchar **lines = g_strsplit(out, "\n", -1);
    gchar *index = NULL, *binary = NULL, *group = NULL;
    int corked = -1;
    gboolean grace = (g_get_monotonic_time() - playing_since) < 3 * G_USEC_PER_SEC;

    for (int i = 0; ; i++) {
        const gchar *l = lines[i];
        gboolean end = (l == NULL) || g_str_has_prefix(l, "Sink Input #");
        if (end && index) {
            /* fin d'un bloc : examen du flux */
            if (g_strcmp0(group, "player") == 0 && g_strcmp0(binary, "soloist") != 0
                && corked >= 0) {
                int now = corked ? 1 : 2;
                int before = GPOINTER_TO_INT(g_hash_table_lookup(stream_corked, index));
                gboolean starts = snapshot_done && now == 2 && before != 2;
                if (starts && wanted && !pause_sent && grace) {
                    /* juste après le départ de Soloist : on attend la fin du
                     * délai avant de juger (l'autre lecteur se met en pause) */
                    if (!check_pending)
                        check_pending = g_timeout_add(1000, check_streams, NULL);
                    g_hash_table_add(seen, g_strdup(index));
                    goto next_block;
                }
                if (starts && wanted && !pause_sent)
                    other_player_started(binary ? binary : "?");
                g_hash_table_insert(stream_corked, g_strdup(index), GINT_TO_POINTER(now));
                g_hash_table_add(seen, g_strdup(index));
            }
        next_block:
            g_clear_pointer(&index, g_free);
            g_clear_pointer(&binary, g_free);
            g_clear_pointer(&group, g_free);
            corked = -1;
        }
        if (l == NULL)
            break;
        const gchar *t = l;
        while (*t == ' ' || *t == '\t')
            t++;
        if (g_str_has_prefix(l, "Sink Input #"))
            index = g_strdup(l + strlen("Sink Input #"));
        else if (g_str_has_prefix(t, "Corked: "))
            corked = g_str_has_prefix(t + 8, "yes");
        else if (g_str_has_prefix(t, "application.process.binary = \""))
            binary = g_strndup(t + 30, strcspn(t + 30, "\""));
        else if (g_str_has_prefix(t, "policy.group = \""))
            group = g_strndup(t + 16, strcspn(t + 16, "\""));
    }
    /* oublie les flux disparus */
    GHashTableIter it;
    gpointer key;
    g_hash_table_iter_init(&it, stream_corked);
    while (g_hash_table_iter_next(&it, &key, NULL))
        if (!g_hash_table_contains(seen, key))
            g_hash_table_iter_remove(&it);
    g_hash_table_destroy(seen);
    g_strfreev(lines);
    g_free(out);
    snapshot_done = TRUE;
    return G_SOURCE_REMOVE;
}

static void start_pactl(void);

static gboolean retry_pactl(gpointer data)
{
    (void)data;
    pactl_retry = 0;
    start_pactl();
    return G_SOURCE_REMOVE;
}

static gboolean pactl_readable(GIOChannel *channel, GIOCondition cond, gpointer data)
{
    (void)data;
    gchar *line = NULL;
    GIOStatus status = G_IO_STATUS_NORMAL;
    if (cond & G_IO_IN) {
        while ((status = g_io_channel_read_line(channel, &line, NULL, NULL, NULL))
               == G_IO_STATUS_NORMAL) {
            if (line && strstr(line, "sink-input") && !check_pending)
                check_pending = g_timeout_add(300, check_streams, NULL);
            g_free(line);
            line = NULL;
        }
    }
    if (status == G_IO_STATUS_EOF || status == G_IO_STATUS_ERROR
        || (cond & (G_IO_HUP | G_IO_ERR))) {
        g_io_channel_shutdown(channel, FALSE, NULL);
        g_io_channel_unref(channel);
        if (!pactl_retry && child > 0)
            pactl_retry = g_timeout_add_seconds(5, retry_pactl, NULL);
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}

static void pactl_exited(GPid pid, gint status, gpointer data)
{
    (void)status; (void)data;
    g_spawn_close_pid(pid);
    if (pid == pactl_pid)
        pactl_pid = 0;
}

static void start_pactl(void)
{
    gchar *argv[] = { "pactl", "subscribe", NULL };
    gint out = -1;
    GError *error = NULL;
    if (pactl_pid || child <= 0)
        return;
    if (!g_spawn_async_with_pipes(NULL, argv, c_environ(),
                                  G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD
                                  | G_SPAWN_STDERR_TO_DEV_NULL,
                                  NULL, NULL, &pactl_pid, NULL, &out, NULL, &error)) {
        gchar *msg = g_strdup_printf("pactl indisponible (%s) : surveillance PulseAudio désactivée",
                                     error->message);
        logmsg(msg);
        g_free(msg);
        g_error_free(error);
        pactl_pid = 0;
        return;
    }
    g_child_watch_add(pactl_pid, pactl_exited, NULL);
    GIOChannel *channel = g_io_channel_unix_new(out);
    g_io_channel_set_close_on_unref(channel, TRUE);
    g_io_channel_set_flags(channel, G_IO_FLAG_NONBLOCK, NULL);
    g_io_add_watch(channel, G_IO_IN | G_IO_HUP | G_IO_ERR, pactl_readable, NULL);
    check_pending = g_timeout_add(300, check_streams, NULL);   /* état initial */
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

    stream_corked = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    start_pactl();
    logmsg("démarrage");

    g_main_loop_run(loop);

    if (trace_pid)
        kill(trace_pid, SIGTERM);
    if (pactl_pid)
        kill(pactl_pid, SIGTERM);
    if (rset) {
        resource_set_release(rset);
        resource_set_destroy(rset);
    }
    return child_status;
}
