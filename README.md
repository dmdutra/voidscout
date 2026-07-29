# voidscout

voidscout scans the [Void Linux](https://voidlinux.org/) srcpkgs tree, stores package metadata in SQLite, and checks upstream sources for newer versions.
The project has two parts:

- **worker** — indexes templates and checks upstream versions
- **web** — Flask frontend to browse packages and download distfiles

## Requirements

- **Worker:** `bash`, `awk`, `sqlite3`, `curl`, `jq`
- **Web:** Python 3.10+ and Flask
- A local checkout of [void-packages](https://github.com/void-linux/void-packages)

## Quick start

Clone void-packages next to voidscout (or point `VOIDSCOUT_REPO` to your checkout):

```text
OpenSource/
├── voidscout/
└── void-packages/
```

### 1. Index packages

```bash
./worker/worker.sh scan
```

This reads all `srcpkgs/*/template` files and writes to `data/voidscout.db`.

### 2. Check upstream versions

```bash
./worker/worker.sh check
```

Use `--limit N` to test with a small number of packages:

```bash
./worker/worker.sh check --limit 10
```

### 3. Run the web UI

```bash
cd web
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

VOIDSCOUT_DB=../data/voidscout.db flask --app app run
```

Open [http://127.0.0.1:5000](http://127.0.0.1:5000) in your browser.

Alternatively:

```bash
VOIDSCOUT_DB=../data/voidscout.db python3 app.py
```

## Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VOIDSCOUT_REPO` | Path to void-packages checkout | `./void-packages` |
| `VOIDSCOUT_DB` | SQLite database path | `data/voidscout.db` |
| `VOIDSCOUT_GITHUB_TOKEN` | GitHub token for higher API rate limits | — |
| `VOIDSCOUT_CHECK_SLEEP` | Delay between upstream HTTP requests (seconds) | `0.1` |

## Supported upstream sources

- GitHub, GitLab, Codeberg
- GNU and Non-GNU (Savannah) mirrors
- kernel.org
- SourceForge
- Generic FTP/HTTP directory listings

## License

See [LICENSE](LICENSE).
