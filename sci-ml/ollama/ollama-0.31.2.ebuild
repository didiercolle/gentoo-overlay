EAPI=8

inherit go-module systemd

DESCRIPTION="Get up and running with large language models locally"
HOMEPAGE="https://ollama.com/ https://github.com/ollama/ollama"

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
	mkdir -p "${WORKDIR}/go-proxy" || die
	unpack "${P}.tar.gz"
	cd "${WORKDIR}/go-proxy" || die
	unpack "${P}-go-proxy.tar.xz"
}

src_compile() {
	export CGO_ENABLED=1
	export CGO_CFLAGS="${CFLAGS} -I/usr/include"
	export CGO_LDFLAGS="${LDFLAGS} -ltree-sitter"

	# Strict CPU optimization configs for your Intel UHD Precision 3470
	export OLLAMA_SKIP_CUDA_GENERATE=1
	export OLLAMA_SKIP_ROCM_GENERATE=1
	export OLLAMA_SKIP_ONEAPI_GENERATE=1
	export OLLAMA_CPU_TARGET="static"

	export GOPROXY="file://${WORKDIR}/go-proxy"
	export GOSUMDB=off

	# STEP 1: Manually trigger the native C++ CMake generation layer for the server runner.
	# This ensures the llama-server binary is output as a plain file we can interact with.
	cmake -S llama/server -B build-llama-server -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DGGML_AVX2=ON \
		-DGGML_FMA=ON \
		|| die "CMake configuration for llama-server failed"
		
	cmake --build build-llama-server || die "Building llama-server failed"

	# STEP 2: Execute the standard Go compilation phase for the client CLI
	go generate ./... || die "go generate failed"
	ego build -o bin/ollama . || die "Failed to build compiled target binary"
}

src_install() {
	# 1. Install primary binary wrapper
	dobin bin/ollama

	# 2. FIXED INSTALLATION: Explicitly install our raw C++ server binary 
	# straight into the main path Ollama searches at runtime.
	exeinto /usr/lib/ollama
	doexe build-llama-server/bin/llama-server

	# 3. Secure data directory layouts
	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama

	# 4. OpenRC Daemon initialization files
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

	# 5. Systemd Unit Configurations
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
