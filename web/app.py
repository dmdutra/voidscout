#!/usr/bin/env python3
import math
import os
import sqlite3
from pathlib import Path
from typing import Optional

from flask import Flask, g, render_template, request

BASE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_DB = BASE_DIR / "data" / "voidscout.db"
PER_PAGE = 50

app = Flask(__name__)
app.config["DATABASE"] = os.environ.get("VOIDSCOUT_DB", str(DEFAULT_DB))


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(app.config["DATABASE"])
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def distfile_download_url(
    distfile: Optional[str], version: str, new_version: Optional[str]
) -> Optional[str]:
    if not distfile:
        return None

    target_version = new_version or version
    if target_version == version:
        return distfile

    for candidate in (version, f"v{version}", f"V{version}"):
        if candidate and candidate in distfile:
            return distfile.replace(candidate, target_version, 1)

    return distfile


def fetch_packages(query: str, page: int, per_page: int):
    db = get_db()
    params: list = []
    where = ""

    if query:
        where = """
            WHERE pkgname LIKE ?
               OR description LIKE ?
               OR version LIKE ?
               OR IFNULL(new_version, '') LIKE ?
        """
        pattern = f"%{query}%"
        params.extend([pattern, pattern, pattern, pattern])

    total = db.execute(f"SELECT COUNT(*) FROM packages {where}", params).fetchone()[0]
    offset = (page - 1) * per_page

    rows = db.execute(
        f"""
        SELECT
            pkgname,
            description,
            version,
            new_version,
            homepage,
            distfile,
            upstream_type,
            scanned_at,
            checked_at
        FROM packages
        {where}
        ORDER BY
            CASE WHEN new_version IS NOT NULL AND new_version != version THEN 0 ELSE 1 END,
            pkgname COLLATE NOCASE
        LIMIT ? OFFSET ?
        """,
        [*params, per_page, offset],
    ).fetchall()

    packages = []
    for row in rows:
        item = dict(row)
        item["download_url"] = distfile_download_url(
            item.get("distfile"),
            item["version"],
            item.get("new_version"),
        )
        packages.append(item)

    return packages, total


def fetch_stats():
    db = get_db()
    row = db.execute(
        """
        SELECT
            COUNT(*) AS total,
            SUM(CASE WHEN new_version IS NOT NULL AND new_version != version THEN 1 ELSE 0 END) AS updates
        FROM packages
        """
    ).fetchone()
    return {"total": row["total"], "updates": row["updates"] or 0}


@app.route("/")
def index():
    query = request.args.get("q", "").strip()
    requested_page = max(request.args.get("page", 1, type=int), 1)

    try:
        _, total = fetch_packages(query, 1, PER_PAGE)
        total_pages = max(math.ceil(total / PER_PAGE), 1)
        page = min(requested_page, total_pages)
        packages, total = fetch_packages(query, page, PER_PAGE)
        stats = fetch_stats()
    except sqlite3.Error:
        app.logger.exception("database error")
        return render_template(
            "index.html",
            packages=[],
            query=query,
            page=1,
            total_pages=0,
            total=0,
            stats={"total": 0, "updates": 0},
            db_error="Could not read the voidscout database. Run the worker scan first.",
        )

    return render_template(
        "index.html",
        packages=packages,
        query=query,
        page=page,
        total_pages=total_pages,
        total=total,
        stats=stats,
        db_error=None,
    )


if __name__ == "__main__":
    app.run(debug=True, host="127.0.0.1", port=5000)
