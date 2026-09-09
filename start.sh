#!/bin/bash

usage() {
    echo "Usage: $0 [options] [services...]"
    echo ""
    echo "Services: wordpress, db (default: all)"
    echo ""
    echo "Options:"
    echo "  -b, --build     Force rebuild images"
    echo "  -d, --detach    Run in background"
    echo "  -s, --stop      Stop running containers"
    echo "  -r, --restart   Restart containers"
    echo "  -l, --logs      Show logs (combine with service names)"
    echo "      --down      Stop and remove containers (database survives)"
    echo "      --reset     Remove containers AND the database volume"
    echo "      --perms     Re-fix wp-content ownership (done automatically on start)"
    echo "      --dump [F]  Write the database to a .sql file (default: dumps/<timestamp>.sql)"
    echo "      --restore [F]  Load a .sql file into the database (default: newest in dumps/)"
    echo "  --status        Show container status"
    echo "  -h, --help      Show this help"
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Docker Desktop and the system Docker daemon are two SEPARATE engines with
# separate containers, images and volumes. Starting or quitting Docker Desktop
# switches which one the "docker" command talks to, which makes a running site
# appear to vanish. Print it, so that is never a mystery.
CTX="$(docker context show 2>/dev/null || echo default)"
echo "==> Docker context: $CTX"

ACTION="up"
BUILD=""

DUMP_DIR="$SCRIPT_DIR/dumps"

# The database lives in a named Docker volume, which is the right place for it:
# InnoDB needs POSIX semantics that a bind mount through Docker Desktop does not
# reliably provide. To move data between machines, or to commit a starting state
# for the class, use a SQL dump instead of copying the raw data directory --
# a dump is portable across MariaDB versions, and it is text, so git can diff it.
dc() { docker compose -f "$COMPOSE_FILE" "$@"; }

require_db() {
    if [ -z "$(dc ps -q db 2>/dev/null)" ]; then
        echo "The db container is not running. Start it first: ./start.sh -d" >&2
        exit 1
    fi
}

# MYSQL_PWD is read from the environment inside the container, so the password
# never appears in a process listing or in the shell history on the host.
do_dump() {
    require_db
    local target="$1"
    if [ -z "$target" ]; then
        mkdir -p "$DUMP_DIR"
        target="$DUMP_DIR/$(date +%Y%m%d-%H%M%S).sql"
    fi
    mkdir -p "$(dirname "$target")"
    echo "==> Dumping database to $target"
    if dc exec -T db sh -c \
        'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -u root --databases "$MARIADB_DATABASE" --single-transaction --routines --events' \
        > "$target"; then
        echo "==> Wrote $(du -h "$target" | cut -f1) to $target"
    else
        rm -f "$target"
        echo "Dump failed." >&2
        exit 1
    fi
}

do_restore() {
    require_db
    local source="$1"
    if [ -z "$source" ]; then
        # Newest dump wins, so "--dump" then "--restore" needs no file name.
        source="$(ls -t "$DUMP_DIR"/*.sql 2>/dev/null | head -1)"
        if [ -z "$source" ]; then
            echo "No .sql file found in $DUMP_DIR -- pass one explicitly:" >&2
            echo "  ./start.sh --restore path/to/file.sql" >&2
            exit 1
        fi
    fi
    if [ ! -f "$source" ]; then
        echo "No such file: $source" >&2
        exit 1
    fi
    # Restoring replaces every post, page and setting currently in the site.
    if [ -z "$ASSUME_YES" ]; then
        echo "This REPLACES the current database with $source."
        printf "Continue? [y/N] "
        read -r reply
        case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
    fi
    echo "==> Restoring from $source"
    if dc exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -u root' < "$source"; then
        echo "==> Restored. Reload the site in your browser."
    else
        echo "Restore failed." >&2
        exit 1
    fi
}

# WordPress runs as www-data (uid 33) and chowns wp-content to itself on first
# boot, which would leave you unable to create a theme without sudo. Hand the
# directory back: owner = you, group = www-data with write. Both sides can then
# write, and no sudo is needed on the host because the chown happens inside the
# container, where we are root.
fix_perms() {
    docker compose -f "$COMPOSE_FILE" exec -T wordpress sh -c \
        "chown -R $(id -u):33 /var/www/html/wp-content && chmod -R g+w /var/www/html/wp-content" \
        2>/dev/null && echo "==> wp-content is writable by $(id -un) and by WordPress"
}
DETACH=""
SERVICES=""
DUMP_FILE=""
ASSUME_YES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--build)   BUILD="--build"; shift ;;
        -d|--detach)  DETACH="-d"; shift ;;
        -s|--stop)    ACTION="stop"; shift ;;
        -r|--restart) ACTION="restart"; shift ;;
        -l|--logs)    ACTION="logs"; shift ;;
        --down)       ACTION="down"; shift ;;
        --reset)      ACTION="reset"; shift ;;
        --perms)      ACTION="perms"; shift ;;
        --dump)       ACTION="dump"; shift
                      case "$1" in ""|-*) ;; *) DUMP_FILE="$1"; shift ;; esac ;;
        --restore)    ACTION="restore"; shift
                      case "$1" in ""|-*) ;; *) DUMP_FILE="$1"; shift ;; esac ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        --status)     ACTION="status"; shift ;;
        -h|--help)    usage; exit 0 ;;
        wordpress|db) SERVICES="$SERVICES $1"; shift ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

case $ACTION in
    up)      docker compose -f "$COMPOSE_FILE" up $BUILD $DETACH $SERVICES
             # Only possible in detached mode; a foreground "up" blocks here
             # until Ctrl-C, so run ./start.sh --perms yourself in that case.
             [ -n "$DETACH" ] && fix_perms ;;
    stop)    docker compose -f "$COMPOSE_FILE" stop $SERVICES ;;
    restart) docker compose -f "$COMPOSE_FILE" restart $SERVICES ;;
    logs)    docker compose -f "$COMPOSE_FILE" logs -f $SERVICES ;;
    status)  docker compose -f "$COMPOSE_FILE" ps ;;
    down)    docker compose -f "$COMPOSE_FILE" down ;;
    reset)   docker compose -f "$COMPOSE_FILE" down -v ;;
    perms)   fix_perms ;;
    dump)    do_dump "$DUMP_FILE" ;;
    restore) do_restore "$DUMP_FILE" ;;
esac
