/*
 * Ingress panel for the Grok Bot client.
 * Serves the static page and a tiny status/control API. It does not read
 * credential files. Sign-in and sign-out are requests to the service, which
 * owns the grokbot-tunnel process.
 */
/* musl does not declare realpath() with _POSIX_C_SOURCE alone. */
#define _XOPEN_SOURCE 700

#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

#define DEFAULT_PORT 8099
#define MAX_REQ 16384
#define MAX_FILE (1024 * 1024)

static const char *web_root = "/opt/panel";
static const char *state_dir = "/run/grokbot";

static int write_all(int fd, const char *buf, size_t len) {
  while (len > 0) {
    ssize_t wrote = write(fd, buf, len);
    if (wrote < 0) {
      if (errno == EINTR) {
        continue;
      }
      return -1;
    }
    buf += wrote;
    len -= (size_t)wrote;
  }
  return 0;
}

static void respond(int fd, int code, const char *reason, const char *type, const char *body, size_t len) {
  char header[768];
  /* An SVG response must not carry the page policy. With nosniff, that policy
   * makes the browser refuse to paint the QR. */
  const char *csp = "";
  if (strncmp(type, "image/", 6) != 0) {
    csp = "Content-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self'\r\n";
  }
  int n = snprintf(header, sizeof header,
                   "HTTP/1.1 %d %s\r\n"
                   "Content-Type: %s\r\n"
                   "Content-Length: %zu\r\n"
                   "Cache-Control: no-store\r\n"
                   "X-Content-Type-Options: nosniff\r\n"
                   "%s"
                   "Connection: close\r\n"
                   "\r\n",
                   code, reason, type, len, csp);
  if (n < 0 || (size_t)n >= sizeof header) {
    return;
  }
  if (write_all(fd, header, (size_t)n) != 0) {
    return;
  }
  if (body != NULL && len > 0) {
    write_all(fd, body, len);
  }
}

static const char *content_type(const char *path) {
  const char *dot = strrchr(path, '.');
  if (dot == NULL) {
    return "application/octet-stream";
  }
  if (strcmp(dot, ".html") == 0) {
    return "text/html; charset=utf-8";
  }
  if (strcmp(dot, ".css") == 0) {
    return "text/css; charset=utf-8";
  }
  if (strcmp(dot, ".js") == 0) {
    return "text/javascript; charset=utf-8";
  }
  if (strcmp(dot, ".svg") == 0) {
    return "image/svg+xml";
  }
  if (strcmp(dot, ".png") == 0) {
    return "image/png";
  }
  if (strcmp(dot, ".json") == 0) {
    return "application/json; charset=utf-8";
  }
  return "application/octet-stream";
}

static int starts_header(const char *p, const char *req, const char *name, size_t name_len) {
  size_t i;
  if (p != req && p[-1] != '\n') {
    return 0;
  }
  for (i = 0; i < name_len; i++) {
    if (tolower((unsigned char)p[i]) != tolower((unsigned char)name[i])) {
      return 0;
    }
  }
  return p[name_len] == ':';
}

static int header_present(const char *req, const char *name) {
  size_t name_len = strlen(name);
  const char *p = req;
  while (*p != '\0') {
    if (starts_header(p, req, name, name_len)) {
      return 1;
    }
    p++;
  }
  return 0;
}

static void serve_file(int fd, const char *url_path) {
  char path[PATH_MAX];
  char resolved[PATH_MAX];
  char root_resolved[PATH_MAX];
  const char *rel = url_path;
  int file;
  struct stat st;
  char *buf;
  size_t got = 0;

  if (strcmp(rel, "/") == 0) {
    rel = "/index.html";
  }
  if (rel[0] != '/' || strstr(rel, "..") != NULL || strchr(rel, '\\') != NULL) {
    respond(fd, 400, "Bad Request", "text/plain; charset=utf-8", "bad path\n", 9);
    return;
  }
  if (snprintf(path, sizeof path, "%s%s", web_root, rel) >= (int)sizeof path) {
    respond(fd, 400, "Bad Request", "text/plain; charset=utf-8", "bad path\n", 9);
    return;
  }
  if (realpath(web_root, root_resolved) == NULL || realpath(path, resolved) == NULL) {
    respond(fd, 404, "Not Found", "text/plain; charset=utf-8", "not found\n", 10);
    return;
  }
  if (strncmp(resolved, root_resolved, strlen(root_resolved)) != 0) {
    respond(fd, 404, "Not Found", "text/plain; charset=utf-8", "not found\n", 10);
    return;
  }
  file = open(resolved, O_RDONLY | O_NOFOLLOW);
  if (file < 0) {
    respond(fd, 404, "Not Found", "text/plain; charset=utf-8", "not found\n", 10);
    return;
  }
  if (fstat(file, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0 || st.st_size > MAX_FILE) {
    close(file);
    respond(fd, 404, "Not Found", "text/plain; charset=utf-8", "not found\n", 10);
    return;
  }
  buf = malloc((size_t)st.st_size);
  if (buf == NULL) {
    close(file);
    respond(fd, 500, "Error", "text/plain; charset=utf-8", "error\n", 6);
    return;
  }
  while (got < (size_t)st.st_size) {
    ssize_t n = read(file, buf + got, (size_t)st.st_size - got);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }
    if (n == 0) {
      break;
    }
    got += (size_t)n;
  }
  close(file);
  respond(fd, 200, "OK", content_type(resolved), buf, got);
  free(buf);
}

static void serve_status(int fd) {
  char path[PATH_MAX];
  const char *fallback =
      "{\"state\":\"starting\",\"status\":\"Not signed in\",\"login_url\":\"\","
      "\"error\":\"\",\"detail\":\"Starting\",\"version\":\"\",\"email\":\"\",\"label\":\"\"}\n";
  char buf[16384];
  int file;
  ssize_t n;

  if (snprintf(path, sizeof path, "%s/status.json", state_dir) >= (int)sizeof path) {
    respond(fd, 500, "Error", "text/plain; charset=utf-8", "error\n", 6);
    return;
  }
  file = open(path, O_RDONLY);
  if (file < 0) {
    respond(fd, 200, "OK", "application/json; charset=utf-8", fallback, strlen(fallback));
    return;
  }
  n = read(file, buf, sizeof buf);
  close(file);
  if (n < 0) {
    respond(fd, 200, "OK", "application/json; charset=utf-8", fallback, strlen(fallback));
    return;
  }
  respond(fd, 200, "OK", "application/json; charset=utf-8", buf, (size_t)n);
}

static int status_is_signed_in(void) {
  char path[PATH_MAX];
  char buf[4096];
  const char *p;
  int file;
  ssize_t n;

  if (snprintf(path, sizeof path, "%s/status.json", state_dir) >= (int)sizeof path) {
    return 0;
  }
  file = open(path, O_RDONLY);
  if (file < 0) {
    return 0;
  }
  n = read(file, buf, sizeof buf - 1);
  close(file);
  if (n < 0) {
    return 0;
  }
  buf[n] = '\0';
  p = strstr(buf, "\"state\"");
  if (p == NULL) {
    return 0;
  }
  p = strchr(p, ':');
  if (p == NULL) {
    return 0;
  }
  p++;
  while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') {
    p++;
  }
  return strncmp(p, "\"connected\"", 11) == 0 || strncmp(p, "\"restarting\"", 12) == 0;
}

static void serve_qr(int fd) {
  char path[PATH_MAX];
  char buf[65536];
  int file;
  size_t got = 0;

  if (snprintf(path, sizeof path, "%s/qr.svg", state_dir) >= (int)sizeof path) {
    respond(fd, 404, "Not Found", "text/plain; charset=utf-8", "not found\n", 10);
    return;
  }
  file = open(path, O_RDONLY);
  if (file < 0) {
    respond(fd, 404, "Not Found", "text/plain; charset=utf-8", "not found\n", 10);
    return;
  }
  while (got < sizeof buf) {
    ssize_t n = read(file, buf + got, sizeof buf - got);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      close(file);
      respond(fd, 404, "Not Found", "text/plain; charset=utf-8", "not found\n", 10);
      return;
    }
    if (n == 0) {
      break;
    }
    got += (size_t)n;
  }
  close(file);
  if (got == 0) {
    respond(fd, 404, "Not Found", "text/plain; charset=utf-8", "not found\n", 10);
    return;
  }
  respond(fd, 200, "OK", "image/svg+xml", buf, got);
}

static int write_control(const char *command) {
  char pattern[PATH_MAX];
  char final_path[PATH_MAX];
  int file;
  size_t len = strlen(command);

  if (mkdir(state_dir, 0755) != 0 && errno != EEXIST) {
    return -1;
  }
  if (snprintf(pattern, sizeof pattern, "%s/control.XXXXXX", state_dir) >= (int)sizeof pattern) {
    return -1;
  }
  if (snprintf(final_path, sizeof final_path, "%s/control", state_dir) >= (int)sizeof final_path) {
    return -1;
  }
  file = mkstemp(pattern);
  if (file < 0) {
    return -1;
  }
  if (write(file, command, len) != (ssize_t)len || write(file, "\n", 1) != 1) {
    close(file);
    unlink(pattern);
    return -1;
  }
  if (fsync(file) != 0) {
    close(file);
    unlink(pattern);
    return -1;
  }
  close(file);
  if (chmod(pattern, 0644) != 0 || rename(pattern, final_path) != 0) {
    unlink(pattern);
    return -1;
  }
  return 0;
}

static void handle(int fd, const char *req) {
  char method[16];
  char path[512];
  char *query;

  if (sscanf(req, "%15s %511s", method, path) != 2) {
    respond(fd, 400, "Bad Request", "text/plain; charset=utf-8", "bad request\n", 12);
    return;
  }
  query = strchr(path, '?');
  if (query != NULL) {
    *query = '\0';
  }

  if (strcmp(method, "GET") == 0 && strcmp(path, "/api/status") == 0) {
    serve_status(fd);
    return;
  }
  if (strcmp(method, "GET") == 0 && strcmp(path, "/qr.svg") == 0) {
    serve_qr(fd);
    return;
  }
  if (strcmp(method, "POST") == 0 &&
      (strcmp(path, "/api/sign-in") == 0 || strcmp(path, "/api/sign-out") == 0)) {
    const char *command = strcmp(path, "/api/sign-in") == 0 ? "sign-in" : "sign-out";
    if (!header_present(req, "X-Grokbot-Panel")) {
      respond(fd, 403, "Forbidden", "text/plain; charset=utf-8", "forbidden\n", 10);
      return;
    }
    if (strcmp(command, "sign-in") == 0 && status_is_signed_in()) {
      respond(fd, 204, "No Content", "text/plain; charset=utf-8", "", 0);
      return;
    }
    if (write_control(command) != 0) {
      respond(fd, 500, "Error", "text/plain; charset=utf-8", "failed\n", 7);
      return;
    }
    respond(fd, 204, "No Content", "text/plain; charset=utf-8", "", 0);
    return;
  }
  if (strcmp(method, "GET") != 0) {
    respond(fd, 405, "Method Not Allowed", "text/plain; charset=utf-8", "method\n", 7);
    return;
  }
  serve_file(fd, path);
}

static int read_request(int fd, char *buf, size_t cap) {
  size_t got = 0;
  while (got + 1 < cap) {
    ssize_t n = read(fd, buf + got, cap - 1 - got);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return -1;
    }
    if (n == 0) {
      break;
    }
    got += (size_t)n;
    buf[got] = '\0';
    if (strstr(buf, "\r\n\r\n") != NULL) {
      return 0;
    }
  }
  buf[got] = '\0';
  return strstr(buf, "\r\n\r\n") != NULL ? 0 : -1;
}

static int listen_on(int port) {
  int server = socket(AF_INET, SOCK_STREAM, 0);
  int enabled = 1;
  struct sockaddr_in addr;

  if (server < 0) {
    return -1;
  }
  setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof enabled);
  memset(&addr, 0, sizeof addr);
  addr.sin_family = AF_INET;
  addr.sin_port = htons((uint16_t)port);
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  if (bind(server, (struct sockaddr *)&addr, sizeof addr) != 0) {
    close(server);
    return -1;
  }
  if (listen(server, 16) != 0) {
    close(server);
    return -1;
  }
  return server;
}

int main(void) {
  const char *port_env = getenv("GROKBOT_PANEL_PORT");
  const char *root_env = getenv("GROKBOT_PANEL_ROOT");
  const char *state_env = getenv("GROKBOT_STATE_DIR");
  int port = DEFAULT_PORT;
  int server;

  if (port_env != NULL && port_env[0] != '\0') {
    port = atoi(port_env);
  }
  if (port < 1 || port > 65535) {
    fprintf(stderr, "invalid GROKBOT_PANEL_PORT\n");
    return 1;
  }
  if (root_env != NULL && root_env[0] != '\0') {
    web_root = root_env;
  }
  if (state_env != NULL && state_env[0] != '\0') {
    state_dir = state_env;
  }

  signal(SIGPIPE, SIG_IGN);
  server = listen_on(port);
  if (server < 0) {
    perror("listen");
    return 1;
  }

  for (;;) {
    int client = accept(server, NULL, NULL);
    char request[MAX_REQ];
    struct timeval timeout;
    if (client < 0) {
      if (errno == EINTR) {
        continue;
      }
      perror("accept");
      return 1;
    }
    timeout.tv_sec = 5;
    timeout.tv_usec = 0;
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
    if (read_request(client, request, sizeof request) == 0) {
      handle(client, request);
    } else {
      respond(client, 400, "Bad Request", "text/plain; charset=utf-8", "bad request\n", 12);
    }
    close(client);
  }
}
