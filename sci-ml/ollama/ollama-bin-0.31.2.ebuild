EAPI=8

inherit systemd

DESCRIPTION="Get up and running with large language models locally (Binary Release)"
HOMEPAGE="https://ollama.com/ https://github.com/ollama/ollama"

# CORRECTED TARGET SUFFIX: Switched from .tgz to .tar.zst as per upstream distribution formats
SRC_URI="https://github.com/${PN}/${PN}/releases/download/v${PV}/ollama-linux-amd64.tar.zst -> ${P}-linux-amd64.tar.zst"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

# MANDATORY DEPENDENCY: We must require app-arch/zstd to process the download archive
BDEPEND="app-arch/zstd"
RDEPEND="
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}"

src_unpack() {
	# Explicitly unpack using zstd decompression flags to handle the stream cleanly
	unpack "${P}-linux-amd64.tar.zst"
}

src_compile() {
	# Pre-compiled static release stream; no compilation routines needed
	:
}

src_install() {
	# 1. Install the core executable binaries
	# The precompiled archive strips files directly into bin/ or your CWD path
	if [[ -f "${S}/bin/ollama" ]]; then
		dobin bin/ollama
	else
		dobin ollama
	fi

	# 2. Setup the persistent system service data directories
	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama

	# 3. Create clean OpenRC init profiles on the fly
	cat <<-'EOF' > "${T}/ollama.init"
		#!/sbin/openrc-run
		description="Ollama Local LLM Service"
		pidfile="/run/ollama.pid"
		command="/usr/bin/ollama"
		command_args="serve"
		command_background="true"
		command_user="ollama:ollama"
		
		# Resource scaling optimization rules for your Precision 3470 laptop hardware
		export OLLAMA_MODELS="/var/lib/ollama/.ollama/models"
		export OLLAMA_CONTEXT_LENGTH=32768
		export OLLAMA_NUM_PARALLEL=1

		depend() {
			need net
		}
	EOF
	newinitd "${T}/ollama.init" ollama

	# 4. Create standard Systemd configuration unit profiles
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
