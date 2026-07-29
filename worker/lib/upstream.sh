#!/bin/bash

# shellcheck source=dirlist.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dirlist.sh"
# shellcheck source=kernel.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kernel.sh"
# shellcheck source=sourceforge.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sourceforge.sh"

detect_upstream() {
	local homepage="${1:-}"
	local distfile="${2:-}"
	local version="${3:-}"
	local url repo upstream_id list_url upstream_type

	for url in "${distfile}" "${homepage}"; do
		[[ -z "${url}" ]] && continue

		if repo="$(extract_github_repo "${url}")"; then
			printf 'github\t%s' "${repo}"
			return 0
		fi

		if repo="$(extract_gitlab_repo "${url}")"; then
			printf 'gitlab\t%s' "${repo}"
			return 0
		fi

		if repo="$(extract_codeberg_repo "${url}")"; then
			printf 'codeberg\t%s' "${repo}"
			return 0
		fi
	done

	if upstream_id="$(extract_sourceforge_upstream "${distfile}" "${version}")"; then
		printf 'sourceforge\t%s' "${upstream_id}"
		return 0
	fi

	if upstream_id="$(extract_kernel_upstream "${distfile}" "${version}")"; then
		printf 'kernel\t%s' "${upstream_id}"
		return 0
	fi

	if upstream_id="$(extract_dirlist_upstream "${distfile}" "${version}")"; then
		list_url="${upstream_id%%"${DIRLIST_SEP}"*}"
		upstream_type="$(classify_dirlist_type "${list_url}")"
		printf '%s\t%s' "${upstream_type}" "${upstream_id}"
		return 0
	fi

	return 1
}

extract_github_repo() {
	local url="${1:-}"

	if [[ "${url}" =~ github\.com/([^/]+)/([^/?#]+) ]]; then
		printf '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
		return 0
	fi

	return 1
}

extract_gitlab_repo() {
	local url="${1:-}"
	local host path

	if [[ "${url}" =~ (gitlab\.[^/]+)/(.+) ]]; then
		host="${BASH_REMATCH[1]}"
		path="${BASH_REMATCH[2]}"
		path="${path%%/-/*}"
		path="${path%%/archive/*}"
		path="${path%%/releases/*}"
		path="${path%%/.git/*}"
		path="${path%.git}"
		printf '%s/%s' "${host}" "${path}"
		return 0
	fi

	return 1
}

extract_codeberg_repo() {
	local url="${1:-}"

	if [[ "${url}" =~ codeberg\.org/([^/]+)/([^/?#]+) ]]; then
		printf '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
		return 0
	fi

	return 1
}

curl_json() {
	local url="$1"
	shift
	local headers=("$@")

	if [[ "${url}" == *"github.com"* && -n "${VOIDSCOUT_GITHUB_TOKEN:-}" ]]; then
		headers+=(-H "Authorization: Bearer ${VOIDSCOUT_GITHUB_TOKEN}")
	fi

	curl -fsSL --connect-timeout 10 --max-time 30 "${headers[@]}" "${url}"
}

fetch_latest_version() {
	local upstream_type="$1"
	local upstream_id="$2"

	case "${upstream_type}" in
	github)
		fetch_github_latest "${upstream_id}"
		;;
	gitlab)
		fetch_gitlab_latest "${upstream_id}"
		;;
	codeberg)
		fetch_codeberg_latest "${upstream_id}"
		;;
	gnu | nongnu | ftp | dirlist | kernel)
		fetch_dirlist_latest "${upstream_id}"
		;;
	sourceforge)
		fetch_sourceforge_latest "${upstream_id}"
		;;
	*)
		return 1
		;;
	esac
}

fetch_github_latest() {
	local owner repo response tag
	owner="${1%%/*}"
	repo="${1#*/}"

	if response="$(curl_json "https://api.github.com/repos/${owner}/${repo}/releases/latest" \
		-H "Accept: application/vnd.github+json" 2>/dev/null)"; then
		tag="$(printf '%s' "${response}" | jq -r '.tag_name // empty' 2>/dev/null || true)"
		if [[ -n "${tag}" ]]; then
			normalize_version "${tag}"
			return 0
		fi
	fi

	if response="$(curl_json "https://api.github.com/repos/${owner}/${repo}/tags?per_page=100" \
		-H "Accept: application/vnd.github+json" 2>/dev/null)"; then
		tag="$(printf '%s' "${response}" | jq -r '.[].name' 2>/dev/null | version_sort_latest || true)"
		if [[ -n "${tag}" ]]; then
			normalize_version "${tag}"
			return 0
		fi
	fi

	return 1
}

fetch_gitlab_latest() {
	local host project_path encoded response tag
	host="${1%%/*}"
	project_path="${1#*/}"
	encoded="$(jq -rn --arg path "${project_path}" '$path|@uri')"

	if response="$(curl_json \
		"https://${host}/api/v4/projects/${encoded}/releases?per_page=1" 2>/dev/null)"; then
		tag="$(printf '%s' "${response}" | jq -r '.[0].tag_name // empty' 2>/dev/null || true)"
		if [[ -n "${tag}" ]]; then
			normalize_version "${tag}"
			return 0
		fi
	fi

	if response="$(curl_json \
		"https://${host}/api/v4/projects/${encoded}/repository/tags?per_page=100" 2>/dev/null)"; then
		tag="$(printf '%s' "${response}" | jq -r '.[].name' 2>/dev/null | version_sort_latest || true)"
		if [[ -n "${tag}" ]]; then
			normalize_version "${tag}"
			return 0
		fi
	fi

	return 1
}

fetch_codeberg_latest() {
	local owner repo response tag
	owner="${1%%/*}"
	repo="${1#*/}"

	if response="$(curl_json "https://codeberg.org/api/v1/repos/${owner}/${repo}/releases?limit=1" 2>/dev/null)"; then
		tag="$(printf '%s' "${response}" | jq -r '.[0].tag_name // empty' 2>/dev/null || true)"
		if [[ -n "${tag}" ]]; then
			normalize_version "${tag}"
			return 0
		fi
	fi

	if response="$(curl_json "https://codeberg.org/api/v1/repos/${owner}/${repo}/tags?limit=100" 2>/dev/null)"; then
		tag="$(printf '%s' "${response}" | jq -r '.[].name' 2>/dev/null | version_sort_latest || true)"
		if [[ -n "${tag}" ]]; then
			normalize_version "${tag}"
			return 0
		fi
	fi

	return 1
}
