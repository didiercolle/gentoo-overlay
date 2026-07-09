EAPI=8

# The go-module eclass handles standard dynamic downloading safely
inherit go-module systemd

DESCRIPTION="Get up and running with large language models locally"
HOMEPAGE="https://ollama.com https://github.com"

# Pure upstream source archive URL
SRC_URI="https://github.com/${PN}/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

# Build tools required inside the build sandbox
BDEPEND="
	>=dev-lang/go-1.22
	dev-build/cmake
	dev-build/ninja
	dev-util/tree-sitter-cli
"

# Bind against Gentoo's system tree-sitter libraries
DEPEND="dev-libs/tree-sitter"
RDEPEND="
	${DEPEND}
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}/${P}"

src_unpack() {
	# Standard source decompression
	default
}

src_compile() {
	export CGO_ENABLED=1
	
	# Instruct CGO to bind directly against standard include directories
	export CGO_CFLAGS="${CFLAGS} -I/usr/include"
	export CGO_LDFLAGS="${LDFLAGS} -ltree-sitter"

	# GPU platform execution skips for Intel UHD hardware
	export OLLAMA_SKIP_CUDA_GENERATE=1
	export OLLAMA_SKIP_ROCM_GENERATE=1
	export OLLAMA_SKIP_ONEAPI_GENERATE=1
	export OLLAMA_CPU_TARGET="static"

	# Let the Go toolchain dynamically generate targets inside Portage's network sandbox
	go generate ./... || die "go generate failed to build llama.cpp backends"
	
	# Regular compilation build sequence
	ego build -o bin/ollama . || die "Failed to build compiled target binary"
}

src_install() {
	dobin bin/ollama

	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama
}
