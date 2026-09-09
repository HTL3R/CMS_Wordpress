# WordPress

A ready-to-run WordPress environment for the WEBT class. Two containers:
WordPress (Apache + PHP) and a MariaDB database. Nothing to install beyond
Docker.

## Requirements

- [Docker](https://docs.docker.com/get-docker/) must be installed.

> **Docker Desktop vs. the system Docker.** These are two separate engines with
> their own containers, images and volumes. Starting or quitting Docker Desktop
> switches which one `docker` talks to, and your running site will seem to have
> vanished — it is simply on the other engine. `./start.sh` prints the active
> context on every run, so check that line first if something disappears.
> Stay on one engine for the whole project.

## Quick start

```bash
./start.sh -d          # start in the background
```

Then open <http://localhost:8080> and complete the WordPress installer once
(site title, admin user, password). Your choices are stored in the database and
survive restarts.

```bash
./start.sh --status    # is it running?
./start.sh -l          # follow the logs
./start.sh -s          # stop, keep everything
./start.sh --down      # remove containers, KEEP the database
./start.sh --reset     # remove containers AND the database (start over)
```

The port is overridable if 8080 is taken:

```bash
HTTP_PORT=9000 ./start.sh -d
```

## Project structure

```
├── wp-content/          # your themes and plugins — edit these on the host
│   ├── themes/
│   └── plugins/
├── docker-compose.yml   # the two services
├── .env                 # shared development defaults (port, DB credentials)
├── start.sh             # start / stop / logs / reset helper
└── README.md
```

WordPress core lives inside the container and is not in this repository. Only
`wp-content/` is shared with the host, which is the part you actually write.

## Where your work goes

- **A theme** → `wp-content/themes/my-theme/` (needs at least `style.css` and
  `index.php`), then activate it under *Appearance → Themes*.
- **A plugin** → `wp-content/plugins/my-plugin/my-plugin.php`, then activate it
  under *Plugins*.

Changes are live: save the file, reload the browser. No rebuild, no restart.

## What is committed, and what is not

`.env` **is** committed on purpose — it holds development defaults that every
student needs, and none of it is secret. The database is not published to the
host, so it is only reachable from the WordPress container.

Your own themes and plugins **are** committed. Things WordPress generates at
runtime are not: `wp-content/uploads/`, `upgrade/`, `cache/` and `debug.log`
are in `.gitignore`.

Put anything genuinely secret in `.env.local` — git ignores it, and Compose
reads it after `.env`.

## File ownership

WordPress runs as `www-data` (uid 33) and takes ownership of `wp-content/` on
first boot, which would stop you creating a theme. `./start.sh -d` fixes this
automatically: the directory ends up owned by **you**, group `www-data` with
write permission, so both you and WordPress can write it. No `sudo` is needed —
the change is made inside the container, where we are root.

If it ever looks wrong again (for example after `--reset`), redo it with:

```bash
./start.sh --perms
```

## Debugging

`WORDPRESS_DEBUG=1` in `.env` makes PHP notices and warnings appear in the page
instead of being swallowed, and errors are also written to
`wp-content/debug.log`. Set it to `0` for a clean-looking site.

## Database dumps

The database lives in a named Docker volume, not in this folder. That is
deliberate: MySQL and MariaDB need filesystem guarantees that a bind mount
through Docker Desktop does not reliably provide, so a `./db:/var/lib/mysql`
mount is slow on macOS and can corrupt the database outright. A raw data
directory is also not portable — a newer server writes a format an older one
refuses to open — and it is thousands of binary files sitting in your project.

Use a SQL dump instead. It is text, it survives version differences, and git
can diff it.

```bash
./start.sh --dump                  # -> dumps/20260909-143000.sql
./start.sh --dump dumps/seed.sql   # a name you choose
./start.sh --restore               # newest file in dumps/
./start.sh --restore dumps/seed.sql
```

`--restore` replaces every post, page and setting currently in the site, so it
asks first. Add `-y` to skip the prompt in a script.

`dumps/` is ignored by git with one exception: **`dumps/seed.sql` is tracked**.
Commit a prepared site there and everyone starts from the same posts, pages and
menus instead of clicking through the installer:

```bash
./start.sh --dump dumps/seed.sql
git add -f dumps/seed.sql && git commit -m "Add seed database"
```

After a fresh clone, or after `--reset`, that state is one command away:

```bash
./start.sh -d && ./start.sh --restore dumps/seed.sql
```

## Resetting

`./start.sh --down` removes the containers but keeps the database.
`./start.sh --reset` throws the database away too and gives you a fresh
installer — take a dump first if you want that site back.
