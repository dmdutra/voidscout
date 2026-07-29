# Parse Void Linux srcpkgs template files.
# Outputs: pkgname<TAB>version<TAB>short_desc<TAB>template_path<TAB>homepage<TAB>distfile

function trim(s) {
	sub(/^[ \t]+/, "", s)
	sub(/[ \t]+$/, "", s)
	return s
}

function parse_value(line, eq, rest, q) {
	eq = index(line, "=")
	if (eq == 0)
		return ""
	rest = trim(substr(line, eq + 1))
	if (rest ~ /^["']/) {
		q = substr(rest, 1, 1)
		if (match(rest, q "[^" q "]*" q))
			return substr(rest, 2, RLENGTH - 2)
		return substr(rest, 2)
	}
	sub(/[ \t#].*$/, "", rest)
	return rest
}

function parse_key(line, eq) {
	eq = index(line, "=")
	if (eq == 0)
		return ""
	return substr(line, 1, eq - 1)
}

function version_major(    parts) {
	split(vars["version"], parts, ".")
	return parts[1]
}

function version_major_minor(    parts, n) {
	n = split(vars["version"], parts, ".")
	if (n >= 2)
		return parts[1] "." parts[2]
	return vars["version"]
}

function version_patch(    parts, n) {
	n = split(vars["version"], parts, ".")
	return parts[n]
}

function resolve_bash_version_expansions(str,    result) {
	result = str
	while (match(result, /\$\{version%%\.\*\}/))
		result = substr(result, 1, RSTART - 1) version_major() substr(result, RSTART + RLENGTH)
	while (match(result, /\$\{version%\.\*\}/))
		result = substr(result, 1, RSTART - 1) version_major_minor() substr(result, RSTART + RLENGTH)
	while (match(result, /\$\{version##\*\.\}/))
		result = substr(result, 1, RSTART - 1) version_patch() substr(result, RSTART + RLENGTH)
	return result
}

function resolve(str, key, val, result) {
	result = resolve_bash_version_expansions(str)
	while (match(result, /\$\{[_a-zA-Z0-9]+\}/)) {
		key = substr(result, RSTART + 2, RLENGTH - 3)
		val = (key in vars) ? vars[key] : ""
		result = substr(result, 1, RSTART - 1) val substr(result, RSTART + RLENGTH)
	}
	while (match(result, /\$[_a-zA-Z0-9]+/)) {
		key = substr(result, RSTART + 1, RLENGTH - 1)
		val = (key in vars) ? vars[key] : ""
		result = substr(result, 1, RSTART - 1) val substr(result, RSTART + RLENGTH)
	}
	return result
}

function sanitize_field(s) {
	gsub(/\t/, " ", s)
	gsub(/\r/, "", s)
	return s
}

BEGIN {
	vars["GNU_SITE"] = "https://ftp.gnu.org/gnu"
	vars["NONGNU_SITE"] = "https://download.savannah.nongnu.org/releases"
	vars["KERNEL_SITE"] = "https://www.kernel.org/pub/linux"
	vars["SOURCEFORGE_SITE"] = "https://downloads.sourceforge.net/sourceforge"
	pkgname = ""
	version = ""
	short_desc = ""
	homepage = ""
	distfile = ""
}

/^[ \t]*#/ || /^[ \t]*$/ {
	next
}

{
	key = parse_key($0)
	val = parse_value($0)

	if (key == "pkgname")
		pkgname = val
	else if (key == "version")
		version = val
	else if (key == "short_desc")
		short_desc = val
	else if (key == "homepage")
		homepage = val
	else if (key == "distfiles" && distfile == "")
		distfile = val

	if (key ~ /^[a-zA-Z_][a-zA-Z0-9_]*$/)
		vars[key] = val
}

END {
	if (pkgname == "" || version == "" || short_desc == "")
		exit 1

	version = resolve(version)
	homepage = resolve(homepage)
	distfile = resolve(distfile)

	print sanitize_field(pkgname) "\t" \
		sanitize_field(version) "\t" \
		sanitize_field(short_desc) "\t" \
		sanitize_field(template_path) "\t" \
		sanitize_field(homepage) "\t" \
		sanitize_field(distfile)
}
