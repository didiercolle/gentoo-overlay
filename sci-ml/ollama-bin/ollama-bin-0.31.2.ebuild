# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

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

# We strictly need zstd and tar at build time to unpack this specific archive layout
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
	# CRITICAL FIX: Bypass Portage's unpack wrapper entirely.
	# Decompress the zstd archive to stdout and pipe it directly into tar to preserve the directory structure.
	zstd -dc "${DISTDIR}/${P}-linux-amd64.tar.zst" | tar -xf - -C "${WORKDIR}" || die "Manual zstd/tar extraction failed"
}

src_compile() {
	# Precompiled binary package; no compiler stages required
	:
}

src_install() {
	# 1. Install the primary client executable directly to /usr/bin/ollama
	into /usr
	if [[ -f "${WORKDIR}/bin/ollama" ]]; then
		dobin bin/ollama
	else
		die "Primary 'ollama' executable missing from expected path. Unpack failed to create bin/ollama folder structure."
	fi

	# 2. Install the backend engines (llama-server) into /usr/lib/ollama/
	exeinto /usr/lib/ollama
	if [[ -d "${WORKDIR}/lib/ollama" ]]; then
		doexe lib/ollama/*
	else
		die "Backend runtime inference engines missing from expected path. Unpack failed to create lib/ollama folder structure."
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
