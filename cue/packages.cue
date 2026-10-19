package mailbag

import (
	"list"
	"strings"
)

// The courier packages the packages image compiles: version and the sha256 of
// each upstream source tarball. The one place they are declared. CI exports
// them as build args for the packages Dockerfile; the install scripts verify
// each download against its sha256 before extracting; scripts/packages-key.sh
// hashes this file, so a bump compiles a new packages image; and
// goss/images/base.yaml checks the base installs these versions.
//
//   cue export ./cue -e packages --out json     # goss vars
//   cue export ./cue -e build_args --out text   # docker build args
//
// The checksums are of the tarballs whose detached signatures verified against
// Courier's release key, Sam Varshavchik <mrsam@courier-mta.com>, fingerprint
// 6EA6 428B 24FF 7A69 6EF9  A483 8A60 F828 A236 52E2 (checked 2026-10-18).

#Package: close({
	version: =~"^[0-9]+\\.[0-9]+(\\.[0-9]+)?$"
	sha256:  =~"^[0-9a-f]{64}$"
})

#Packages: close({
	courier:         #Package
	courier_authlib: #Package
	courier_unicode: #Package
	sysconftool:     #Package
})

packages: #Packages & {
	courier: {
		version: "2.0.8"
		sha256:  "a9da6739d2cf8bf5e80fd63b08ec163fa4a70a9bcc765dd1d0e1b8327785ca60"
	}
	courier_authlib: {
		version: "0.73.2"
		sha256:  "8629a3af9a169fc64e9f8fd6aafd320ba42c2443db15bf97e9f6076fe6dda618"
	}
	courier_unicode: {
		version: "2.6.0"
		sha256:  "0aed2349c5b62de0d33ccf8c23527aae41daf95a03c8054c88de4faef8da8a08"
	}
	sysconftool: {
		version: "0.22"
		sha256:  "34962bb554be726e6a852fbc04fd56123f69f9dd6f48cee8e25eb5a1a42f4e05"
	}
}

// One NAME_VERSION= and NAME_SHA256= line per package, the names the install
// scripts read: courier_authlib -> COURIER_AUTHLIB_VERSION. Sorted, so the
// export is stable.
build_args: strings.Join([
	for k in list.SortStrings([for k, _ in packages {k}]) {
		let n = strings.ToUpper(k)
		"\(n)_VERSION=\(packages[k].version)\n\(n)_SHA256=\(packages[k].sha256)"
	},
], "\n")
