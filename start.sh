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
esac
