EAPI=8

inherit systemd

DESCRIPTION="Get up and running with large language models locally (Binary Release)"
HOMEPAGE="https://ollama.com/ https://github.com/ollama/ollama"

# Target the official static binary release for AMD64 architectures
SRC_URI="https://github.com/ollama/ollama/releases/download/v${PV}/ollama-linux-amd64.tar.zst -> ${P}-linux-amd64.tar.zst"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

# Required decompression package
BDEPEND="app-arch/zstd"
RDEPEND="
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}"

src_unpack() {
	# Extract the uncompressed data streams safely into the temporary workspace
	unpack "${P}-linux-amd64.tar.zst"
}

src_compile() {
	# Pure static binary deployment; no compilation phases required
	:
}

src_install() {
	# 1. FIXED BINARY TRACKING: Deploy the primary client wrapper binary explicitly
	into /usr
	if [[ -f "${S}/bin/ollama" ]]; then
		dobin bin/ollama
	elif [[ -f "${S}/ollama" ]]; then
		doexe ollama
	else
		die "Primary ollama executable wrapper missing from tarball package payload"
	fi

	# 2. FIXED SERVER LOGIC: Extract and copy the embedded runner engines (llama-server)
	# Upstream places them inside the 'lib/ollama/' folder of the tarball
	exeinto /usr/lib/ollama
	if [[ -d "${S}/lib/ollama" ]]; then
		doexe lib/ollama/*
	fi

	# 3. Setup persistent system model storage directory parameters
	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama

	# 4. Deploy clean OpenRC init script environments
	cat <<-'EOF' > "${T}/ollama.init"
		#!/sbin/openrc-run
		description="Ollama Local LLM Service"
		pidfile="/run/ollama.pid"
		command="/usr/bin/ollama"
		command_args="serve"
		command_background="true"
		command_user="ollama:ollama"
		
		# Core execution scaling variables tailored for your Intel UHD Precision laptop
		export OLLAMA_MODELS="/var/lib/ollama/.ollama/models"
		export OLLAMA_CONTEXT_LENGTH=32768
		export OLLAMA_NUM_PARALLEL=1

		depend() {
			need net
		}
	EOF
	newinitd "${T}/ollama.init" ollama

	# 5. Deploy Systemd Unit target templates
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
