FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

RUN apt-get update && apt-get install -y --no-install-recommends \
	ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
	bzip2 ca-certificates ccache clang cmake cpio curl device-tree-compiler \
	fastjar file flex g++ g++-14 gawk gcc gcc-14 gcc-multilib genisoimage gettext \
	git gperf haveged help2man intltool libelf-dev libfuse-dev libglib2.0-dev \
	libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev \
	libpython3-dev libreadline-dev libssl-dev libtool libyaml-dev llvm lrzsz \
	mksh mold msmtp nano ninja-build p7zip p7zip-full patch pkgconf python3 \
	python3-pip python3-ply python3-pyelftools qemu-utils rsync scons squashfs-tools \
	subversion swig texinfo uglifyjs unzip upx-ucl vim wget xmlto xxd zlib1g-dev \
	golang-go sudo time rename \
	&& rm -rf /var/lib/apt/lists/*

RUN if getent passwd 1000 >/dev/null; then \
		existing_user="$(getent passwd 1000 | cut -d: -f1)"; \
		existing_group="$(getent group 1000 | cut -d: -f1 || true)"; \
		[ "${existing_user}" = "builder" ] || usermod -l builder "${existing_user}"; \
		if [ -n "${existing_group}" ] && [ "${existing_group}" != "builder" ]; then groupmod -n builder "${existing_group}"; fi; \
		usermod -d /home/builder -m builder; \
	else \
		useradd -m -u 1000 -s /bin/bash builder; \
	fi \
	&& echo 'builder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/builder

USER builder
WORKDIR /workspace

CMD ["bash", "scripts/build-openwrt.sh"]
