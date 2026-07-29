#!/bin/bash

DIRLIST_SEP='|'

is_plausible_version() {
	local version="${1:-}"

	[[ "${version}" =~ [0-9] ]] || return 1

	case "${version}" in
	latest | current | stable | snapshot | master | trunk | HEAD | head)
		return 1
		;;
	esac

	return 0
}

classify_dirlist_type() {
	local list_url="$1"

	case "${list_url}" in
	*ftp.gnu.org/gnu/* | *ftp.gnu.org/pub/gnu/*)
		printf 'gnu'
		;;
	*download.savannah.nongnu.org/releases/*)
		printf 'nongnu'
		;;
	*kernel.org/pub/linux/*)
		printf 'kernel'
		;;
	*downloads.sourceforge.net/*)
		printf 'sourceforge'
		;;
	ftp://*)
		printf 'ftp'
		;;
	*)
		printf 'dirlist'
		;;
	esac
}

extract_dirlist_upstream() {
	local distfile="${1:-}"
	local version="${2:-}"
	local filename dir_url prefix suffix candidate

	[[ -n "${distfile}" && -n "${version}" ]] || return 1

	filename="${distfile##*/}"
	dir_url="${distfile%/*}/"

	[[ "${dir_url}" =~ ^(https?|ftp):// ]] || return 1

	for candidate in "${version}" "v${version}" "V${version}" "$(normalize_version "${version}")"; do
		[[ -z "${candidate}" ]] && continue
		[[ "${filename}" == *"${candidate}"* ]] || continue

		prefix="${filename%%"${candidate}"*}"
		suffix="${filename#*"${candidate}"}"

		if [[ -n "${prefix}" && -n "${suffix}" ]]; then
			printf '%s%s%s%s%s' "${dir_url}" "${DIRLIST_SEP}" "${prefix}" "${DIRLIST_SEP}" "${suffix}"
			return 0
		fi
	done

	return 1
}

curl_listing() {
	local url="$1"

	curl -fsSL --connect-timeout 10 --max-time 30 "${url}"
}

listing_candidates() {
	local listing="$1"

	printf '%s\n' "${listing}" | grep -oE 'href="[^"]+"' | sed 's/href="//;s/"$//'
	printf '%s\n' "${listing}" | grep -oE 'href='\''[^'\'']+'\''' | sed "s/href='//;s/'$//"
	printf '%s\n' "${listing}" | awk '{
		for (i = 1; i <= NF; i++) {
			if ($i ~ /^[A-Za-z0-9][A-Za-z0-9._+-]*\.(tar\.(gz|bz2|xz)|tgz|zip)$/)
				print $i
		}
	}'
}

extract_versions_from_listing() {
	local listing="$1"
	local prefix="$2"
	local suffix="$3"
	local series_filter="${4:-}"
	local candidate file version

	while IFS= read -r candidate; do
		[[ -z "${candidate}" ]] && continue
		[[ "${candidate}" == "." || "${candidate}" == ".." ]] && continue
		[[ "${candidate}" == */ ]] && continue

		file="${candidate%%\?*}"
		file="${file%%#*}"
		file="${file##*/}"

		[[ "${file}" == "${prefix}"*"${suffix}" ]] || continue

		version="${file#"${prefix}"}"
		version="${version%"${suffix}"}"
		[[ -n "${version}" ]] || continue
		is_plausible_version "${version}" || continue
		matches_series_filter "${version}" "${series_filter}" || continue

		printf '%s\n' "${version}"
	done < <(listing_candidates "${listing}" | sort -u)
}

fetch_dirlist_latest() {
	local upstream_id="$1"
	local list_url prefix suffix series_filter listing latest

	IFS="${DIRLIST_SEP}" read -r list_url prefix suffix series_filter <<<"${upstream_id}"

	[[ -n "${list_url}" && -n "${prefix}" && -n "${suffix}" ]] || return 1

	if ! listing="$(curl_listing "${list_url}")"; then
		return 1
	fi

	latest="$(extract_versions_from_listing "${listing}" "${prefix}" "${suffix}" "${series_filter}" | version_sort_latest || true)"
	[[ -n "${latest}" ]] || return 1

	normalize_version "${latest}"
}
