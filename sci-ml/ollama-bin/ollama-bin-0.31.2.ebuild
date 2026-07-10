EAPI=8

inherit systemd

DESCRIPTION="Get up and running with large language models locally (Binary Release)"
HOMEPAGE="https://ollama.com https://github.com"

# Point to the official static binary release
SRC_URI="https://github.com/ollama/ollama/releases/download/v${PV}/ollama-linux-amd64.tar.zst -> ${P}-linux-amd64.tar.zst"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

# We strictly need app-arch/zstd and app-arch/tar on the host system to run extraction
BDEPEND="
	app-arch/zstd
	app-arch/tar
"
RDEPEND="
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}"

src_unpack() {
	# NO MORE PORTAGE UNPACK GHOSTING.
	# We force decompression using the absolute direct system binary paths 
	# to extract the archive explicitly into the sandbox work folder.
	/usr/bin/zstd -dc "${DISTDIR}/${P}-linux-amd64.tar.zst" | /bin/tar -xf - -C "${WORKDIR}" || die "Extraction failed"
}

src_compile() {
	# Binary package - no compilation steps
	:
}

src_install() {
	# Ensure directory configurations match our real layout
	into /usr
	
	# Install client wrapper binary
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
