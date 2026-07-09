EAPI=8

inherit go-module systemd

DESCRIPTION="Get up and running with large language models locally"
HOMEPAGE="https://ollama.com https://github.com"

# Main source plus the local/GitHub hosted unpruned proxy asset archive
SRC_URI="https://github.com{PN}/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	https://localhost/${P}-go-proxy.tar.xz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

BDEPEND="
	>=dev-lang/go-1.22
	dev-build/cmake
	dev-build/ninja
	dev-util/tree-sitter-cli
"
DEPEND="dev-libs/tree-sitter"
RDEPEND="
	${DEPEND}
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}/${P}"

src_unpack() {
	# Create a strict target folder for the local dependency mirror mapping
	mkdir -p "${WORKDIR}/go-proxy" || die
	
	# Unpack the main app codebase
	unpack "${P}.tar.gz"
	
	# Extract the unpruned Go zip streams natively inside the proxy silo
	cd "${WORKDIR}/go-proxy" || die
	unpack "${P}-go-proxy.tar.xz"
}

src_compile() {
	export CGO_ENABLED=1
	export CGO_CFLAGS="${CFLAGS} -I/usr/include"
	export CGO_LDFLAGS="${LDFLAGS} -ltree-sitter"

	# GPU platform hardware runtime skips for your Intel UHD configuration
	export OLLAMA_SKIP_CUDA_GENERATE=1
	export OLLAMA_SKIP_ROCM_GENERATE=1
	export OLLAMA_SKIP_ONEAPI_GENERATE=1
	export OLLAMA_CPU_TARGET="static"

	# THE CORE OFFLINE SANDBOX FIX:
	# Convert Go's target proxy pipeline to use your local filesystem layout
	export GOPROXY="file://${WORKDIR}/go-proxy"
	export GOSUMDB=off

	# Run code generation (now pulls tree-sitter C files directly from the offline zip)
	go generate ./... || die "go generate failed to build llama.cpp backends"
	
	# Compile final standalone binary
	ego build -o bin/ollama . || die "Failed to build compiled target binary"
}

src_install() {
	# 1. Install the compiled binary target
	dobin bin/ollama

	# 2. Setup persistent system directory
	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama

	# 3. Explicitly create and install the OpenRC init script
	cat <<-'EOF' > "${T}/ollama.init"
		#!/sbin/openrc-run
		description="Ollama Local LLM Service"
		pidfile="/run/ollama.pid"
		command="/usr/bin/ollama"
		command_args="serve"
		command_background="true"
		command_user="ollama:ollama"
		export OLLAMA_MODELS="/var/lib/ollama/.ollama/models"
		export OLLAMA_CONTEXT_LENGTH=32768
		export OLLAMA_NUM_PARALLEL=1
		depend() { need net; }
	EOF
	newinitd "${T}/ollama.init" ollama

	# 4. Explicitly create and install the Systemd service descriptor
	cat <<-'EOF' > "${T}/ollama.service"
		[Unit]
		Description=Ollama Service
		After=network-online.target

		[Service]
		ExecStart=/usr/bin/ollama serve
		User=ollama
		Group=ollama
		Restart=always
		RestartSec=3
		Environment="OLLAMA_MODELS=/var/lib/ollama/.ollama/models"
		Environment="OLLAMA_CONTEXT_LENGTH=32768"
		Environment="OLLAMA_NUM_PARALLEL=1"

		[Install]
		WantedBy=default.target
	EOF
	systemd_dounit "${T}/ollama.service"
}
