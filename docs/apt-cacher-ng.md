# Speeding up pi-gen builds with apt-cacher-ng

Each pi-gen build downloads hundreds of Debian packages during `debootstrap`
(stage0) and the per-stage `apt-get install` runs. Running a local
apt-cacher-ng proxy on your LAN turns every rebuild after the first into a
near-instant operation, and also makes builds resilient to flaky upstream
Debian mirrors.

Once it is running, point pi-gen at it by adding one line to the `config`
file:

```
APT_PROXY=http://<cacher-host>:3142
```

Stage0 wires this into the image's `/etc/apt/apt.conf.d/51cache`, so both the
build itself and the running Pi (on first boot) go through the cache.

**Important:** use the LAN IP/hostname of the cacher host, not `localhost` or
`127.0.0.1`. The build runs inside a Docker container, so `localhost` refers
to the container itself. On macOS Docker Desktop, `host.docker.internal`
works as a shortcut for "the Docker host".

---

## Setting it up on Linux (recommended)

apt-cacher-ng is a native Debian/Ubuntu package and runs as a system
service. This is the simplest and most reliable option.

### 1. Install and start the service

```bash
sudo apt-get install apt-cacher-ng
sudo systemctl enable --now apt-cacher-ng
```

It listens on port 3142 on all interfaces by default.

### 2. Pin the upstream mirror

The default config picks mirrors from a bundled random list, and some of
those mirrors return occasional errors that get cached and poison future
requests. Pinning a single reliable upstream avoids this.

Check the backends file:

```bash
cat /etc/apt-cacher-ng/backends_debian
```

If empty, add the canonical Debian mirror:

```bash
echo 'http://deb.debian.org/debian/' | sudo tee /etc/apt-cacher-ng/backends_debian
sudo systemctl restart apt-cacher-ng
```

### 3. Verify it works

```bash
curl -sI -x http://localhost:3142 http://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.xz
```

Expected: `HTTP/1.1 200 OK` with a multi-megabyte `Content-Length`. If you
get `500 Remote or cache error` or a tiny `Content-Length` (e.g. 673 bytes),
the cache has stored a bad response — see Troubleshooting below.

### 4. Point pi-gen at it

On the machine running pi-gen, edit `config` and add:

```
APT_PROXY=http://<linux-host-ip>:3142
```

e.g. `APT_PROXY=http://192.168.1.50:3142`.

### Status page

Web UI: `http://<linux-host>:3142/acng-report.html` — shows cache size, hit
rate, and has buttons to expire/purge cached files without touching the
filesystem.

---

## Setting it up on macOS

Homebrew does not ship apt-cacher-ng, so the easiest path on macOS is to
run it in Docker.

### 1. Start the container

A helper script is included in this repo:

```bash
./scripts/start-apt-cacher.sh
```

It is idempotent — reuses the container if it already exists, creates a
named Docker volume (`apt-cacher-ng-cache`) so the cache survives container
recreations, and prints the line to add to `config` when ready.

Or do it by hand:

```bash
docker run -d \
  --name apt-cacher-ng \
  --restart=always \
  -p 3142:3142 \
  -v apt-cacher-ng-cache:/var/cache/apt-cacher-ng \
  sameersbn/apt-cacher-ng
```

### 2. Point pi-gen at it

The pi-gen build also runs in Docker, so it needs to reach the host. Add to
`config`:

```
APT_PROXY=http://host.docker.internal:3142
```

`host.docker.internal` is the special hostname Docker Desktop provides for
"the host running Docker".

### 3. Verify

```bash
curl -sI -x http://localhost:3142 http://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.xz
```

Same expectation: 200 OK, multi-megabyte `Content-Length`.

---

## Troubleshooting

### `500 Remote or cache error` or tiny (hundreds-of-bytes) responses

apt-cacher-ng has cached an error response from a flaky upstream mirror.
Clear the cache:

```bash
sudo systemctl stop apt-cacher-ng
sudo rm -rf /var/cache/apt-cacher-ng/*
sudo chown -R apt-cacher-ng:apt-cacher-ng /var/cache/apt-cacher-ng
sudo systemctl start apt-cacher-ng
```

(On macOS/Docker: `docker exec apt-cacher-ng rm -rf /var/cache/apt-cacher-ng/* && docker restart apt-cacher-ng`.)

Then make sure `backends_debian` pins a reliable upstream (see step 2 of
the Linux setup above) so the problem doesn't recur.

### Debootstrap fails with `Couldn't download ... Packages`

Usually the same cause — a cached error response. Purge and retry as above.

### `Error reading from server. Remote end closed connection` on a specific `.deb`

Symptom: the build fetches most packages fine, then fails on one specific
file with "Remote end closed connection" or "500 Remote or cache error".
The apt-cacher-ng log shows a mismatch between bytes fetched from upstream
and the file's real size — e.g. only 4 KB fetched for a 27 KB file.

This is usually **a corrupt response cached by Fastly** (the CDN in front
of `deb.debian.org`). You can confirm by fetching the file directly from
the Linux host, bypassing apt-cacher-ng:

```bash
curl -fI http://deb.debian.org/debian/pool/main/d/dconf/dconf-cli_0.40.0-5_arm64.deb
curl -fsSL http://deb.debian.org/debian/pool/main/d/dconf/dconf-cli_0.40.0-5_arm64.deb -o /tmp/check.deb
ls -l /tmp/check.deb
```

If the headers advertise (say) 27868 bytes but `curl` finishes early with
`transfer closed with N bytes remaining to read`, and the `Age:` header on
the response is large (hours or days), you're hitting a stuck corrupt
entry on a Fastly edge node. There's nothing you can do to flush that
edge cache.

**Fix: switch apt-cacher-ng to a non-CDN mirror.** `ftp.us.debian.org`
(and most country-code mirrors) are plain round-robin DNS over actual
Debian mirror servers, with no CDN in between.

```bash
echo 'http://ftp.us.debian.org/debian/' | sudo tee /etc/apt-cacher-ng/backends_debian
sudo rm -rf /var/cache/apt-cacher-ng/debrep/
sudo systemctl restart apt-cacher-ng
```

Verify the file comes through complete:

```bash
curl -fsSL -x http://localhost:3142 http://deb.debian.org/debian/pool/main/d/dconf/dconf-cli_0.40.0-5_arm64.deb -o /tmp/check.deb
ls -l /tmp/check.deb
```

Byte count should match the `Content-Length` from upstream. Then rerun
the pi-gen build.

Note: pi-gen's `config` still references `deb.debian.org` — apt-cacher-ng's
`Remap-debrep` rewrites the backend transparently, so no client-side
change is needed.

### Build still slow on first run

Expected. The cache is cold on the first build; it only accelerates
subsequent builds. The first build through a fresh cache runs at the speed
of your upstream connection.

### Checking what the cache is doing

Tail the log while a build runs:

```bash
sudo tail -F /var/log/apt-cacher-ng/apt-cacher.log
```

Columns: `timestamp|direction|bytes|client-ip|path`. `I` = bytes fetched
from upstream (cache miss), `O` = bytes served to client. A warm cache
should show mostly `O` lines with no matching `I`.
