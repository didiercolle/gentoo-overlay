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
	# Schakel CGO in voor de lokale C++ bindings
	export CGO_ENABLED=1
	
	# HIER ZIT DE CRUCIALE FIX voor de sandbox:
	# We blokkeren expliciet elke poging om GPU backends te zoeken of bouwen.
	export OLLAMA_SKIP_CUDA_GENERATE=1
	export OLLAMA_SKIP_ROCM_GENERATE=1
	export OLLAMA_SKIP_ONEAPI_GENERATE=1
	
	# Zorg dat hij puur de CPU-bibliotheek bouwt zonder extra netwerk-downloads
	export OLLAMA_CPU_TARGET="static"

	# Voer de code-generator uit met de lokale vendor bibliotheken
	go generate -mod=vendor ./... || die "go generate failed to build llama.cpp backends"
	
	# Bouw de uiteindelijke Gentoo binary
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
