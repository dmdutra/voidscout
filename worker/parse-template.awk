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

function resolve(str, key, val, result) {
	result = str
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
