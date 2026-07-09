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

# Required decompression dependency package
BDEPEND="app-arch/zstd"
RDEPEND="
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}"

src_unpack() {
	# Extract the zstd compressed archive cleanly into the root of ${WORKDIR}
	unpack "${P}-linux-amd64.tar.zst"
}

src_compile() {
	# Precompiled binary package; no compiler stages required
	:
}

src_install() {
	# 1. FIXED EXECUTABLE DEPLOYMENT:
	# Install the primary binary into /usr/bin/ using the explicit workspace sub-path
	exeinto /usr/bin
	if [[ -f "${S}/bin/ollama" ]]; then
		doexe bin/ollama
	else
		die "Primary 'ollama' client executable wrapper missing from extracted 'bin/' path"
	fi

	# 2. FIXED BACKEND ENGINE DEPLOYMENT:
	# Copy the companion llama-server engines into /usr/lib/ollama/
	exeinto /usr/lib/ollama
	if [[ -d "${S}/lib/ollama" ]]; then
		doexe lib/ollama/*
	else
		die "Backend runtime inference engines missing from extracted 'lib/ollama/' path"
	fi

	# 3. Setup the persistent system data boundary storage directory
	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama

	# 4. Deploy clean OpenRC init profiles on the fly
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

	# 5. Deploy standard Systemd Unit configuration profiles
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
