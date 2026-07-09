EAPI=8

inherit go-module systemd

DESCRIPTION="Get up and running with large language models locally"
HOMEPAGE="https://ollama.com https://github.com"

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

	go generate ./... || die "go generate failed to build llama.cpp backends"
	ego build -o bin/ollama . || die "Failed to build compiled target binary"
}

src_install() {
	# 1. Install the primary client wrapper binary
	dobin bin/ollama

	# 2. HARDENED INSTALLATION MATCHING THE CPU PRESET TARGETS:
	# Ollama's build system creates specific preset sub-folders inside 'build/'
	exeinto /usr/lib/ollama
	
	if [[ -f "build/llama-server-cpu/bin/llama-server" ]]; then
		doexe "build/llama-server-cpu/bin/llama-server"
	elif [[ -f "build/llama-server-cpu/llama-server" ]]; then
		doexe "build/llama-server-cpu/llama-server"
	elif [[ -d "lib/ollama" && -f "lib/ollama/llama-server" ]]; then
		doexe lib/ollama/*
	else
		# Absolute fallback: unconstrained recursive search for matching targets
		local fallback_bin=$(find "${WORKDIR}" -name "llama-server" -type f -executable | head -n 1)
		if [[ -n "${fallback_bin}" ]]; then
			doexe "${fallback_bin}"
		else
			die "llama-server binary could not be found anywhere inside the work directory tree"
		fi
	fi

	# 3. Setup persistent system model storage directory boundaries
	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama

	# 4. Deploy OpenRC Daemon initialization profiles
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

	# 5. Deploy Systemd Unit Profiles
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
