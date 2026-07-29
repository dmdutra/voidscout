#!/bin/bash

extract_sourceforge_upstream() {
	local distfile="${1:-}"
	local version="${2:-}"
	local path filename dir_path project subpath last_dir prefix suffix candidate

	[[ -n "${distfile}" && -n "${version}" ]] || return 1
	[[ "${distfile}" == *downloads.sourceforge.net/sourceforge/* ]] || return 1

	path="${distfile#*downloads.sourceforge.net/sourceforge/}"
	filename="${path##*/}"
	dir_path="${path%/*}"

	project="${dir_path%%/*}"
	subpath="${dir_path#*/}"
	if [[ "${subpath}" == "${project}" ]]; then
		subpath=""
	fi

	if [[ -n "${subpath}" ]]; then
		last_dir="${subpath##*/}"
		if [[ "${last_dir}" == "${version}" || "${last_dir}" == *"${version}"* ]]; then
			subpath="${subpath%/*}"
		fi
	fi

	for candidate in "${version}" "v${version}" "V${version}" "$(normalize_version "${version}")"; do
		[[ -z "${candidate}" ]] && continue
		[[ "${filename}" == *"${candidate}"* ]] || continue

		prefix="${filename%%"${candidate}"*}"
		suffix="${filename#*"${candidate}"}"

		if [[ -n "${prefix}" && -n "${suffix}" ]]; then
			printf '%s%s%s%s%s%s%s' \
				"${project}" "${DIRLIST_SEP}" "${subpath}" "${DIRLIST_SEP}" \
				"${prefix}" "${DIRLIST_SEP}" "${suffix}"
			return 0
		fi
	done

	return 1
}

curl_sourceforge_rss() {
	local project="$1"
	local sf_path="$2"
	local rss_url

	sf_path="${sf_path#/}"
	if [[ -n "${sf_path}" ]]; then
		rss_url="https://sourceforge.net/projects/${project}/rss?path=/${sf_path}"
	else
		rss_url="https://sourceforge.net/projects/${project}/rss"
	fi

	curl -fsSL --connect-timeout 10 --max-time 30 \
		-A "voidscout/0.1 (+https://github.com/voidlinux/voidscout)" \
		"${rss_url}"
}

sourceforge_listing_paths() {
	local listing="$1"

	printf '%s' "${listing}" | grep -oE '<title><!\[CDATA\[[^]]+\]\]></title>' |
		sed 's/<title><!\[CDATA\[//;s/\]\]><\/title>//'
}

extract_versions_from_sourceforge() {
	local listing="$1"
	local prefix="$2"
	local suffix="$3"
	local item_path file version

	while IFS= read -r item_path; do
		[[ -z "${item_path}" ]] && continue

		file="${item_path##*/}"
		[[ "${file}" == "${prefix}"*"${suffix}" ]] || continue

		version="${file#"${prefix}"}"
		version="${version%"${suffix}"}"
		[[ -n "${version}" ]] || continue
		is_plausible_version "${version}" || continue

		printf '%s\n' "${version}"
	done < <(sourceforge_listing_paths "${listing}" | sort -u)
}

fetch_sourceforge_latest() {
	local upstream_id="$1"
	local project sf_path prefix suffix listing latest

	IFS="${DIRLIST_SEP}" read -r project sf_path prefix suffix <<<"${upstream_id}"

	[[ -n "${project}" && -n "${prefix}" && -n "${suffix}" ]] || return 1

	if ! listing="$(curl_sourceforge_rss "${project}" "${sf_path}")"; then
		return 1
	fi

	latest="$(extract_versions_from_sourceforge "${listing}" "${prefix}" "${suffix}" | version_sort_latest || true)"
	[[ -n "${latest}" ]] || return 1

	normalize_version "${latest}"
}
