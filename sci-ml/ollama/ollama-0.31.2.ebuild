EAPI=8

# Inherit go-module to handle offline dependency sandboxing
inherit go-module systemd

DESCRIPTION="Get up and running with large language models locally"
HOMEPAGE="https://ollama.com/ https://github.com/ollama/ollama"

# Clean Gentoo formatting matching original source release tarballs
SRC_URI="https://github.com/${PN}/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

# Go compiler required for building from source
BDEPEND=">=dev-lang/go-1.22"
RDEPEND="
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}/${P}"

src_compile() {
	# Force Ollama to compile the underlying CGO code using CPU execution targets
	export CGO_ENABLED=1
	
	# Generate embedded llama.cpp logic 
	go generate ./... || die "go generate failed to build llama.cpp backends"
	
	# Standard Gentoo Go compilation syntax
	ego build -o bin/ollama . || die "Failed to build ollama binary"
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
