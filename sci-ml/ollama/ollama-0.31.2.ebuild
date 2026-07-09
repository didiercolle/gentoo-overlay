EAPI=8

# Inherit go-module to handle offline dependency sandboxing
inherit go-module systemd

DESCRIPTION="Get up and running with large language models locally"
HOMEPAGE="https://ollama.com/ https://github.com/ollama/ollama"

# Clean Gentoo formatting matching original source release tarballs
SRC_URI="https://github.com/${PN}/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
         https://localhost/${P}-deps.tar.xz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

# Go compiler required for building from source
BDEPEND="
	>=dev-lang/go-1.22
	dev-build/cmake
	dev-build/ninja
"
RDEPEND="
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}/${P}"

src_unpack() {
	# Unpack the main source archive and the dependencies archive
	default
}

src_compile() {
	# Force Ollama to run fully local on CGO
	export CGO_ENABLED=1
	
	# CRITICAL FIX: Force the generator script to ONLY target the CPU back-end.
	# This bypasses the network-dependent detection steps for CUDA, ROCm, and OneAPI assets.
	export OLLAMA_CUSTOM_CPU_ONLY=1
	export OLLAMA_SKIP_CPU_GENERATE=0
	
	# Instruct go generate to use the local vendor bundle cache rather than hitting the WAN
	go generate -mod=vendor ./... || die "go generate failed to build llama.cpp backends"
	
	# Final native build
	ego build -mod=vendor -o bin/ollama . || die "Failed to build compiled target binary"
}

src_install() {
	# Installs our fresh locally compiled binary target
	dobin bin/ollama

	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama

	# Setup OpenRC script
	newinitd - "${PN}" <<-'EOF'
		#!/sbin/openrc-run
		description="Ollama Local LLM Service"
		pidfile="/run/ollama.pid"
		command="/usr/bin/ollama"
		command_args="serve"
		command_background="true"
		command_user="ollama:ollama"
		export OLLAMA_MODELS="/var/lib/ollama/.ollama/models"
		export OLLAMA_CONTEXT_LENGTH=32768
		depend() { need net; }
	EOF

	# Setup Systemd if flag is active
	if use systemd; then
		systemd_newunit - "${PN}.service" <<-'EOF'
			[Unit]
			Description=Ollama Service
			After=network-online.target

			[Service]
			ExecStart=/usr/bin/ollama serve
			User=ollama
			Group=ollama
			Restart=always
			Environment="OLLAMA_MODELS=/var/lib/ollama/.ollama/models"
			Environment="OLLAMA_CONTEXT_LENGTH=32768"

			[Install]
			WantedBy=default.target
		EOF
	fi
}
