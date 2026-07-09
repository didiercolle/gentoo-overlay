EAPI=8

inherit systemd

DESCRIPTION="Get up and running with large language models locally (Binary Release)"
HOMEPAGE="https://ollama.com https://github.com"

# Target the official static binary release for AMD64 architectures
SRC_URI="https://github.com/ollama/ollama/releases/download/v${PV}/ollama-linux-amd64.tar.zst -> ${P}-linux-amd64.tar.zst"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

# We only need zstd at build time to unpack the archive
BDEPEND="app-arch/zstd"
RDEPEND="
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}"

src_unpack() {
	# Unpack the zstd-compressed tarball into ${WORKDIR}
	unpack "${P}-linux-amd64.tar.zst"
}

src_compile() {
	# Pre-compiled binaries require no compilation phase
	:
}

src_install() {
	# 1. Install the main ollama client CLI binary
	into /usr
	if [[ -f "${S}/bin/ollama" ]]; then
		dobin bin/ollama
	else
		die "Primary 'ollama' executable missing from expected 'bin/' path"
	fi

	# 2. Install the backend engines (llama-server) into the runtime path
	exeinto /usr/lib/ollama
	if [[ -d "${S}/lib/ollama" ]]; then
		doexe lib/ollama/*
	else
		die "Backend library directory 'lib/ollama/' missing from payload"
	fi

	# 3. Setup persistent system model storage boundaries
	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama

	# 4. Create OpenRC init files
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

		depend() {
			need net
		}
	EOF
	newinitd "${T}/ollama.init" ollama

	# 5. Create Systemd unit configuration
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
