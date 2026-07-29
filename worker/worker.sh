#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly AWK_PARSER="${SCRIPT_DIR}/parse-template.awk"

# shellcheck source=lib/version-compare.sh
source "${SCRIPT_DIR}/lib/version-compare.sh"
# shellcheck source=lib/upstream.sh
source "${SCRIPT_DIR}/lib/upstream.sh"

REPO_DIR="${VOIDSCOUT_REPO:-${PROJECT_DIR}/../v}"
DB_PATH="${VOIDSCOUT_DB:-${PROJECT_DIR}/data/voidscout.db}"
CHECK_SLEEP="${VOIDSCOUT_CHECK_SLEEP:-0.1}"

usage() {
	cat <<EOF
Usage: $(basename "$0") <command> [options]

Voidscout worker for Void Linux srcpkgs.

Environment:
  VOIDSCOUT_REPO           Path to void-packages checkout (default: ../v)
  VOIDSCOUT_DB             SQLite database path (default: data/voidscout.db)
  VOIDSCOUT_GITHUB_TOKEN   GitHub token for higher API rate limits
  VOIDSCOUT_CHECK_SLEEP    Delay between upstream HTTP requests (default: 0.1)

Commands:
  scan                     Scan templates and update package metadata
  check [--limit N]        Check upstream versions for supported packages
  help                     Show this help
EOF
}

require_command() {
	local command_name="$1"
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		echo "error: required command '${command_name}' not found" >&2
		exit 1
	fi
}

sql_escape() {
	printf "%s" "$1" | sed "s/'/''/g"
}

ensure_column() {
	local table="$1"
	local column="$2"
	local definition="$3"

	if ! sqlite3 "${DB_PATH}" "PRAGMA table_info(${table});" | awk -F'|' -v col="${column}" '$2 == col { found=1 } END { exit !found }'; then
		sqlite3 "${DB_PATH}" "ALTER TABLE ${table} ADD COLUMN ${column} ${definition};"
	fi
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
	homepage TEXT,
	distfile TEXT,
	upstream_type TEXT,
	upstream_id TEXT,
	checked_at TEXT,
	check_error TEXT,
	scanned_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS upstreams (
	upstream_key TEXT PRIMARY KEY,
	upstream_type TEXT NOT NULL,
	upstream_id TEXT NOT NULL,
	latest_version TEXT,
	checked_at TEXT,
	check_error TEXT
);

CREATE INDEX IF NOT EXISTS idx_packages_new_version
	ON packages (new_version)
	WHERE new_version IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_packages_upstream
	ON packages (upstream_type, upstream_id)
	WHERE upstream_type IS NOT NULL;
SQL

	ensure_column packages homepage TEXT
	ensure_column packages distfile TEXT
	ensure_column packages upstream_type TEXT
	ensure_column packages upstream_id TEXT
	ensure_column packages checked_at TEXT
	ensure_column packages check_error TEXT
}

scan_repo() {
	local srcpkgs="${REPO_DIR}/srcpkgs"
	local template parsed pkgname version description template_path homepage distfile
	local upstream upstream_type upstream_id
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

			IFS=$'\t' read -r pkgname version description template_path homepage distfile <<<"${parsed}"

			upstream_type=""
			upstream_id=""
			if upstream="$(detect_upstream "${homepage}" "${distfile}")"; then
				IFS=$'\t' read -r upstream_type upstream_id <<<"${upstream}"
			fi

			cat <<SQL
INSERT INTO packages (
	pkgname, description, version, new_version, template_path,
	homepage, distfile, upstream_type, upstream_id, scanned_at
)
VALUES (
	'$(sql_escape "${pkgname}")',
	'$(sql_escape "${description}")',
	'$(sql_escape "${version}")',
	NULL,
	'$(sql_escape "${template_path}")',
	'$(sql_escape "${homepage}")',
	'$(sql_escape "${distfile}")',
	$(if [[ -n "${upstream_type}" ]]; then printf "'%s'" "$(sql_escape "${upstream_type}")"; else printf 'NULL'; fi),
	$(if [[ -n "${upstream_id}" ]]; then printf "'%s'" "$(sql_escape "${upstream_id}")"; else printf 'NULL'; fi),
	datetime('now')
)
ON CONFLICT(pkgname) DO UPDATE SET
	description = excluded.description,
	version = excluded.version,
	template_path = excluded.template_path,
	homepage = excluded.homepage,
	distfile = excluded.distfile,
	upstream_type = excluded.upstream_type,
	upstream_id = excluded.upstream_id,
	scanned_at = excluded.scanned_at,
	new_version = CASE
		WHEN packages.version != excluded.version THEN NULL
		ELSE packages.new_version
	END,
	checked_at = CASE
		WHEN packages.version != excluded.version
			OR packages.upstream_type IS NOT excluded.upstream_type
			OR packages.upstream_id IS NOT excluded.upstream_id
		THEN NULL
		ELSE packages.checked_at
	END,
	check_error = CASE
		WHEN packages.version != excluded.version
			OR packages.upstream_type IS NOT excluded.upstream_type
			OR packages.upstream_id IS NOT excluded.upstream_id
		THEN NULL
		ELSE packages.check_error
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

get_upstream_cache() {
	local upstream_key="$1"
	sqlite3 "${DB_PATH}" "SELECT latest_version, check_error FROM upstreams WHERE upstream_key = '$(sql_escape "${upstream_key}")';"
}

save_upstream_cache() {
	local upstream_key="$1"
	local upstream_type="$2"
	local upstream_id="$3"
	local latest_version="$4"
	local check_error="$5"

	sqlite3 "${DB_PATH}" <<SQL
INSERT INTO upstreams (upstream_key, upstream_type, upstream_id, latest_version, checked_at, check_error)
VALUES (
	'$(sql_escape "${upstream_key}")',
	'$(sql_escape "${upstream_type}")',
	'$(sql_escape "${upstream_id}")',
	$(if [[ -n "${latest_version}" ]]; then printf "'%s'" "$(sql_escape "${latest_version}")"; else printf 'NULL'; fi),
	datetime('now'),
	$(if [[ -n "${check_error}" ]]; then printf "'%s'" "$(sql_escape "${check_error}")"; else printf 'NULL'; fi)
)
ON CONFLICT(upstream_key) DO UPDATE SET
	upstream_type = excluded.upstream_type,
	upstream_id = excluded.upstream_id,
	latest_version = excluded.latest_version,
	checked_at = excluded.checked_at,
	check_error = excluded.check_error;
SQL
}

update_package_check() {
	local pkgname="$1"
	local new_version="$2"
	local check_error="$3"
	local new_version_sql="NULL"

	if [[ -n "${new_version}" ]]; then
		new_version_sql="'$(sql_escape "${new_version}")'"
	fi

	sqlite3 "${DB_PATH}" <<SQL
UPDATE packages
SET
	new_version = ${new_version_sql},
	checked_at = datetime('now'),
	check_error = $(if [[ -n "${check_error}" ]]; then printf "'%s'" "$(sql_escape "${check_error}")"; else printf 'NULL'; fi)
WHERE pkgname = '$(sql_escape "${pkgname}")';
SQL
}

resolve_upstream_latest() {
	local upstream_type="$1"
	local upstream_id="$2"
	local upstream_key="${upstream_type}:${upstream_id}"
	local cache_line latest_version check_error fetch_error

	cache_line="$(get_upstream_cache "${upstream_key}")"
	if [[ -n "${cache_line}" ]]; then
		IFS='|' read -r latest_version check_error <<<"${cache_line}"
		if [[ -n "${check_error}" ]]; then
			return 1
		fi
		printf '%s' "${latest_version}"
		return 0
	fi

	if ! latest_version="$(fetch_latest_version "${upstream_type}" "${upstream_id}")"; then
		fetch_error="failed to fetch upstream version"
		save_upstream_cache "${upstream_key}" "${upstream_type}" "${upstream_id}" "" "${fetch_error}"
		return 1
	fi

	save_upstream_cache "${upstream_key}" "${upstream_type}" "${upstream_id}" "${latest_version}" ""
	sleep "${CHECK_SLEEP}"
	printf '%s' "${latest_version}"
}

check_versions() {
	local limit=""
	local pkgname version upstream_type upstream_id latest_version
	local checked_count=0 updated_count=0 failed_count=0 skipped_count=0
	local query

	require_command curl
	require_command jq
	require_command sqlite3
	init_db

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--limit)
			limit="$2"
			shift 2
			;;
		*)
			echo "error: unknown option '$1'" >&2
			exit 1
			;;
		esac
	done

	query="SELECT pkgname, version, upstream_type, upstream_id
		FROM packages
		WHERE upstream_type IS NOT NULL
		  AND upstream_id IS NOT NULL
		ORDER BY pkgname"

	if [[ -n "${limit}" ]]; then
		query="${query} LIMIT ${limit}"
	fi

	echo "Checking upstream versions..."

	while IFS='|' read -r pkgname version upstream_type upstream_id; do
		if ! latest_version="$(resolve_upstream_latest "${upstream_type}" "${upstream_id}")"; then
			update_package_check "${pkgname}" "" "failed to fetch upstream version"
			failed_count=$((failed_count + 1))
			continue
		fi

		if version_gt "${latest_version}" "${version}"; then
			update_package_check "${pkgname}" "${latest_version}" ""
			echo "${pkgname}: ${version} -> ${latest_version}"
			updated_count=$((updated_count + 1))
		else
			update_package_check "${pkgname}" "" ""
			skipped_count=$((skipped_count + 1))
		fi

		checked_count=$((checked_count + 1))
	done < <(sqlite3 -separator '|' "${DB_PATH}" "${query}")

	echo "Done. Checked ${checked_count}, updates found ${updated_count}, up to date ${skipped_count}, failed ${failed_count}."
	echo "Database: ${DB_PATH}"
}

main() {
	local command="${1:-}"

	case "${command}" in
	scan)
		scan_repo
		;;
	check)
		shift
		check_versions "$@"
		;;
	"" | -h | --help | help)
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
