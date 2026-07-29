#!/bin/bash

matches_series_filter() {
	local version="${1:-}"
	local series="${2:-}"

	[[ -z "${series}" ]] && return 0
	[[ "${version}" == "${series}" ]] && return 0
	[[ "${version}" == "${series}."* ]]
}

extract_kernel_upstream() {
	local distfile="${1:-}"
	local version="${2:-}"
	local dir_url series

	[[ -n "${distfile}" && -n "${version}" ]] || return 1
	[[ "${distfile}" == *kernel.org/pub/linux/kernel/* ]] || return 1

	if [[ "${distfile}" =~ /kernel/(v[0-9]+\.x)/ ]]; then
		dir_url="https://www.kernel.org/pub/linux/kernel/${BASH_REMATCH[1]}/"
		series="${version%.*}"
		printf '%s%s%s%s%s%s%s' \
			"${dir_url}" "${DIRLIST_SEP}" "patch-" "${DIRLIST_SEP}" ".xz" \
			"${DIRLIST_SEP}" "${series}"
		return 0
	fi

	return 1
}
