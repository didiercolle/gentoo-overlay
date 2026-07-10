EAPI=8

# unpacker eclass natively adds support for .tar.zst archives inside the sandbox
inherit systemd unpacker

DESCRIPTION="Get up and running with large language models locally (Binary Release)"
HOMEPAGE="https://ollama.com https://github.com"

# Target the official static binary release
SRC_URI="https://github.com/ollama/ollama/releases/download/v${PV}/ollama-linux-amd64.tar.zst -> ${P}-linux-amd64.tar.zst"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

# The unpacker eclass handles adding the correct decompression tools to BDEPEND automatically
BDEPEND=""
RDEPEND="
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}"

src_unpack() {
	# unpacker_src_unpack is the official eclass function that safely handles 
	# the sandboxed decompression of the .tar.zst archive without any bash pipes.
	unpacker_src_unpack
}

src_compile() {
	:
}

src_install() {
	into /usr
	
	# Verify extraction and install client wrapper binary
	if [[ -f "${WORKDIR}/bin/ollama" ]]; then
		dobin bin/ollama
	else
		die "Primary 'ollama' executable missing from workspace extraction target"
	fi

	# Install server library packages
	exeinto /usr/lib/ollama
	if [[ -d "${WORKDIR}/lib/ollama" ]]; then
		doexe lib/ollama/*
	fi

	# Setup persistent data directories
	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama

	# Deploy OpenRC system initialization configurations
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

	# Deploy Systemd system daemon service configurations
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
