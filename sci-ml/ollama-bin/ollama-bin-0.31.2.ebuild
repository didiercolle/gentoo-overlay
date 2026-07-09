EAPI=8

inherit systemd

DESCRIPTION="Get up and running with large language models locally (Binary Release)"
HOMEPAGE="https://ollama.com https://github.com"

# Target the official pre-compiled static release archive
SRC_URI="https://github.com/ollama/ollama/releases/download/v${PV}/ollama-linux-amd64.tar.zst -> ${P}-linux-amd64.tar.zst"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

# CRITICAL NATIVE FIX: We register app-arch/zstd so Portage's built-in 
# unpack system can natively handle .zst streams without shell pipes.
BDEPEND="app-arch/zstd"
RDEPEND="
	acct-group/ollama
	acct-user/ollama
"

S="${WORKDIR}"

src_unpack() {
	# Let Portage handle the sandboxed extraction natively
	unpack "${P}-linux-amd64.tar.zst"
}

src_compile() {
	# Precompiled binary package; no compiler stages required
	:
}

src_install() {
	# 1. Install the main client binary wrapper
	into /usr
	if [[ -f "${WORKDIR}/bin/ollama" ]]; then
		dobin bin/ollama
	elif [[ -f "${WORKDIR}/ollama" ]]; then
		dobin ollama
	else
		# Safety fallback: search recursively if paths are flat
		local fallback_bin=$(find "${WORKDIR}" -type f -name "ollama" -executable | head -n 1)
		if [[ -n "${fallback_bin}" ]]; then
			dobin "${fallback_bin}"
		else
			die "Primary 'ollama' executable missing from workspace"
		fi
	fi

	# 2. Install the companion inference engines (llama-server)
	exeinto /usr/lib/ollama
	if [[ -d "${WORKDIR}/lib/ollama" ]]; then
		doexe lib/ollama/*
	else
		local fallback_server=$(find "${WORKDIR}" -type f -name "llama-server" -executable | head -n 1)
		if [[ -n "${fallback_server}" ]]; then
			doexe "${fallback_server}"
		fi
	fi

	# 3. Setup the persistent system data boundary storage directory
	diropts -o ollama -g ollama -m 0750
	keepdir /var/lib/ollama

	# 4. Deploy clean OpenRC init profiles
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
