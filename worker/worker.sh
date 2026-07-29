#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly AWK_PARSER="${SCRIPT_DIR}/parse-template.awk"

REPO_DIR="${VOIDSCOUT_REPO:-${PROJECT_DIR}/../v}"
DB_PATH="${VOIDSCOUT_DB:-${PROJECT_DIR}/data/voidscout.db}"

usage() {
	cat <<EOF
Usage: $(basename "$0") [scan]

Scan the Void Linux srcpkgs repository and store package metadata in SQLite.

Environment:
  VOIDSCOUT_REPO  Path to void-packages checkout (default: ../v)
  VOIDSCOUT_DB    SQLite database path (default: data/voidscout.db)

Commands:
  scan            Scan all templates and update the database (default)
EOF
}

sql_escape() {
	printf "%s" "$1" | sed "s/'/''/g"
}

init_db() {
	mkdir -p "$(dirname "${DB_PATH}")"

	sqlite3 "${DB_PATH}" <<'SQL' >/dev/null
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS packages (
	pkgname TEXT PRIMARY KEY,
	description TEXT NOT NULL,
	version TEXT NOT NULL,
	new_version TEXT,
	template_path TEXT NOT NULL,
	scanned_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_packages_new_version
	ON packages (new_version)
	WHERE new_version IS NOT NULL;
SQL
}

scan_repo() {
	local srcpkgs="${REPO_DIR}/srcpkgs"
	local template parsed pkgname version description template_path
	local parsed_count=0 skipped_count=0
	local sql_file

	if [[ ! -d "${srcpkgs}" ]]; then
		echo "error: srcpkgs directory not found at ${srcpkgs}" >&2
		exit 1
	fi

	if [[ ! -f "${AWK_PARSER}" ]]; then
		echo "error: parser not found at ${AWK_PARSER}" >&2
		exit 1
	fi

	echo "Scanning ${srcpkgs}..."
	init_db

	sql_file="$(mktemp)"
	{
		echo "BEGIN;"
		while IFS= read -r -d '' template; do
			if ! parsed="$(awk -v template_path="${template}" -f "${AWK_PARSER}" "${template}" 2>/dev/null)"; then
				skipped_count=$((skipped_count + 1))
				echo "warning: skipped ${template}" >&2
				continue
			fi

			IFS=$'\t' read -r pkgname version description template_path <<<"${parsed}"

			cat <<SQL
INSERT INTO packages (pkgname, description, version, new_version, template_path, scanned_at)
VALUES (
	'$(sql_escape "${pkgname}")',
	'$(sql_escape "${description}")',
	'$(sql_escape "${version}")',
	NULL,
	'$(sql_escape "${template_path}")',
	datetime('now')
)
ON CONFLICT(pkgname) DO UPDATE SET
	description = excluded.description,
	version = excluded.version,
	template_path = excluded.template_path,
	scanned_at = excluded.scanned_at,
	new_version = CASE
		WHEN packages.version != excluded.version THEN NULL
		ELSE packages.new_version
	END;
SQL
			parsed_count=$((parsed_count + 1))
		done < <(find "${srcpkgs}" -mindepth 2 -maxdepth 2 -name template -type f -print0)
		echo "COMMIT;"
	} >"${sql_file}"

	sqlite3 "${DB_PATH}" <"${sql_file}"
	rm -f "${sql_file}"

	echo "Done. Parsed ${parsed_count} packages, skipped ${skipped_count}."
	echo "Database: ${DB_PATH}"
}

main() {
	local command="${1:-scan}"

	case "${command}" in
	scan)
		scan_repo
		;;
	-h | --help | help)
		usage
		;;
	*)
		echo "error: unknown command '${command}'" >&2
		usage >&2
		exit 1
		;;
	esac
}

main "$@"
