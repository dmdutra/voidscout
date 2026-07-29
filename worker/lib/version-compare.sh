#!/bin/bash

normalize_version() {
	local version="${1:-}"
	version="${version#v}"
	version="${version#V}"
	version="${version#release-}"
	version="${version#Release-}"
	printf '%s' "${version}"
}

version_gt() {
	local left right newest
	left="$(normalize_version "$1")"
	right="$(normalize_version "$2")"

	[[ -z "${left}" || -z "${right}" ]] && return 1
	[[ "${left}" == "${right}" ]] && return 1

	newest="$(printf '%s\n' "${left}" "${right}" | sort -V | tail -1)"
	[[ "${newest}" == "${left}" ]]
}

version_sort_latest() {
	sort -V | tail -1
}
