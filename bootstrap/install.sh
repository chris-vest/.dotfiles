#!/bin/bash

setup_sudo() {
	# add user to sudoers
	adduser "$TARGET_USER" sudo

	# add user to systemd groups
	# then you wont need sudo to view logs and shit
	gpasswd -a "$TARGET_USER" systemd-journal
	gpasswd -a "$TARGET_USER" systemd-network

	# create docker group
	sudo groupadd docker
	sudo gpasswd -a "$TARGET_USER" docker

	# add go path to secure path
	{ \
		echo -e "Defaults	secure_path=\"/usr/local/go/bin:/home/${TARGET_USER}/.go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/share/bcc/tools\""; \
		echo -e 'Defaults	env_keep += "ftp_proxy http_proxy https_proxy no_proxy GOPATH EDITOR"'; \
		echo -e "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL"; \
		echo -e "${TARGET_USER} ALL=NOPASSWD: /sbin/ifconfig, /sbin/ifup, /sbin/ifdown, /sbin/ifquery"; \
	} >> /etc/sudoers

	# setup downloads folder as tmpfs
	# that way things are removed on reboot
	# i like things clean but you may not want this
	mkdir -p "/home/$TARGET_USER/Downloads"
	echo -e "\\n# tmpfs for downloads\\ntmpfs\\t/home/${TARGET_USER}/Downloads\\ttmpfs\\tnodev,nosuid,size=2G\\t0\\t0" >> /etc/fstab
}

basic_apt() {
	sudo apt update || true

	sudo apt upgrade -y || true

	sudo apt install -y \
		apt-transport-https \
		ca-certificates \
		curl \
		dirmngr \
		gnupg2 \
		lsb-release \
		--no-install-recommends

	# turn off translations, speed up apt update
	mkdir -p /etc/apt/apt.conf.d
	echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99translations

	sudo apt update || true
	sudo apt -y upgrade

	sudo apt install -y \
		adduser \
		automake \
		bash-completion \
		bc \
		bzip2 \
		ca-certificates \
		coreutils \
		curl \
		docker.io \
		dnsutils \
		file \
		findutils \
		gcc \
		git \
		git-core \
		gnupg \
		gnupg2 \
		grep \
		gzip \
		hostname \
		i3 \
		indent \
		iptables \
		jq \
		keepassx \
		less \
		libc6-dev \
		locales \
		lsof \
		make \
		mount \
		mysql-shell \
		nautilus-dropbox
		net-tools \
		neovim \
		openvpn \
		python3-pip \
		python3-setuptools \
		ssh \
		strace \
		sudo \
		tar \
		tmux \
		tree \
		tzdata \
		unzip \
		xss-lock \
		xz-utils \
		zip \
		zsh \
		--no-install-recommends
	
	pip3 install awscli

	sudo snap install kubectl --classic
}

setup_oh_my_zsh() {
	wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh
	chsh -s `which zsh`
}

setup_git() {
	echo "Git setup"

	ssh-add ~/.ssh/id_rsa

	git config --global core.editor vim
	git config --global user.name chris-vest
	git config --global user.email hotdogsandfrenchfries@gmail.com
}

install_vim() {
	# create subshell
	(
	cd "$HOME"

	# install .vim files
	sudo rm -rf "${HOME}/.vim"
	git clone --recursive git@github.com:jessfraz/.vim.git "${HOME}/.vim"
	(
	cd "${HOME}/.vim"
	make install
	)

	# update alternatives to neovim
	sudo update-alternatives --install /usr/bin/vi vi "$(command -v nvim)" 60
	sudo update-alternatives --config vi
	sudo update-alternatives --install /usr/bin/vim vim "$(command -v nvim)" 60
	sudo update-alternatives --config vim
	sudo update-alternatives --install /usr/bin/editor editor "$(command -v nvim)" 60
	sudo update-alternatives --config editor

	# install things needed for deoplete for vim
	sudo apt update || true

	sudo apt install -y \
		python3-pip \
		python3-setuptools \
		--no-install-recommends

	pip3 install -U \
		setuptools \
		wheel \
		neovim
	)
}

install_dropbox() {
	cd ~ && wget -O - "https://www.dropbox.com/download?plat=lnx.x86_64" | tar xzf -
	~/.dropbox-dist/dropboxd && exit 0
}

install_1password() {
	arm=$(dpkg --print-architecture)
	curl -o /tmp/op.zip https://cache.agilebits.com/dist/1P/op/pkg/v0.5.5/op_linux_${arm}_v0.5.5.zip
	unzip /tmp/op.zip /tmp/
	chmod u+x /tmp/op
	sudo mv /tmp/op /usr/local/bin/
}

install_light() {
	echo "Install Light"
	mkdir ~/projects
	cd ~/projects
	git clone https://github.com/haikarainen/light.git
	cd light
	./autogen.sh
	./configure && make
	sudo make install
}

install_vault() {
	mkdir -p ~/go/src/github.com/hashicorp && cd $_
    git clone https://github.com/hashicorp/vault.git
    cd vault
	make bootstrap
	make dev
}

install_terraform() {
	curl -o /tmp/terraform.zip https://releases.hashicorp.com/terraform/0.11.11/terraform_0.11.11_linux_amd64.zip
	unzip /tmp/terraform.zip /tmp/
	chmod u+x /tmp/terraform
	sudo mv /tmp/terraform /usr/local/bin/
}

install_gcp() {
	# Create environment variable for correct distribution
	export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"

	# Add the Cloud SDK distribution URI as a package source
	echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

	# Import the Google Cloud Platform public key
	curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

	# Update the package list and install the Cloud SDK
	sudo apt-get update && sudo apt-get install google-cloud-sdk
}

# install/update golang from source
install_golang() {
	export GO_VERSION
	GO_VERSION=$(curl -sSL "https://golang.org/VERSION?m=text")
	export GO_SRC=/usr/local/go

	# if we are passing the version
	if [[ ! -z "$1" ]]; then
		GO_VERSION=$1
	fi

	# purge old src
	if [[ -d "$GO_SRC" ]]; then
		sudo rm -rf "$GO_SRC"
		sudo rm -rf "$GOPATH"
	fi

	GO_VERSION=${GO_VERSION#go}

	# subshell
	(
	kernel=$(uname -s | tr '[:upper:]' '[:lower:]')
	curl -sSL "https://storage.googleapis.com/golang/go${GO_VERSION}.${kernel}-amd64.tar.gz" | sudo tar -v -C /usr/local -xz
	local user="$USER"
	# rebuild stdlib for faster builds
	sudo chown -R "${user}" /usr/local/go/pkg
	CGO_ENABLED=0 /usr/local/bin/go install -a -installsuffix cgo std
	)

	GOPATH="/home/crystal/go"

	# get commandline tools
	(
	set -x
	set +e
	/usr/local/go/bin/go get github.com/golang/lint/golint
	/usr/local/go/bin/go get golang.org/x/tools/cmd/cover
	/usr/local/go/bin/go get golang.org/x/review/git-codereview
	/usr/local/go/bin/go get golang.org/x/tools/cmd/goimports
	/usr/local/go/bin/go get golang.org/x/tools/cmd/gorename
	/usr/local/go/bin/go get golang.org/x/tools/cmd/guru

	/usr/local/go/bin/go get github.com/genuinetools/amicontained
	/usr/local/go/bin/go get github.com/genuinetools/apk-file
	/usr/local/go/bin/go get github.com/genuinetools/audit
	/usr/local/go/bin/go get github.com/genuinetools/bpfd
	/usr/local/go/bin/go get github.com/genuinetools/bpfps
	/usr/local/go/bin/go get github.com/genuinetools/certok
	/usr/local/go/bin/go get github.com/genuinetools/netns
	/usr/local/go/bin/go get github.com/genuinetools/pepper
	/usr/local/go/bin/go get github.com/genuinetools/reg
	/usr/local/go/bin/go get github.com/genuinetools/udict
	/usr/local/go/bin/go get github.com/genuinetools/weather

	/usr/local/go/bin/go get github.com/axw/gocov/gocov
	/usr/local/go/bin/go get honnef.co/go/tools/cmd/staticcheck

	# Tools for vimgo.
	/usr/local/go/bin/go get github.com/jstemmer/gotags
	/usr/local/go/bin/go get github.com/nsf/gocode
	/usr/local/go/bin/go get github.com/rogpeppe/godef

	aliases=( genuinetools/contained.af genuinetools/binctr genuinetools/img docker/docker moby/buildkit opencontainers/runc )
	for project in "${aliases[@]}"; do
		owner=$(dirname "$project")
		repo=$(basename "$project")
		if [[ -d "${HOME}/${repo}" ]]; then
			rm -rf "${HOME:?}/${repo}"
		fi

		mkdir -p "${GOPATH}/src/github.com/${owner}"

		if [[ ! -d "${GOPATH}/src/github.com/${project}" ]]; then
			(
			# clone the repo
			cd "${GOPATH}/src/github.com/${owner}"
			git clone "https://github.com/${project}.git"
			# fix the remote path, since our gitconfig will make it git@
			cd "${GOPATH}/src/github.com/${project}"
			git remote set-url origin "https://github.com/${project}.git"
			)
		else
			echo "found ${project} already in gopath"
		fi
	done
	)

	# symlink weather binary for motd
	sudo ln -snf "${GOPATH}/bin/weather" /usr/local/bin/weather
}

set_config() {
	# add aliases for dotfiles
	for file in $(shell find $(CURDIR) -name ".*" -not -name ".gitignore" -not -name ".git"); do
		f=$$(basename $$file)
		ln -sfn $$file $(HOME)/$$f
	done
	
	mkdir -p $(HOME)/.config/dunst
	ln -snf $(CURDIR)/.config/dunst/dunstrc

	mkdir -p $(HOME)/.i3
	cp -sR $(CURDIR)/.i3/ $(HOME)/.i3/

	sudo cp -sR $(CURDIR)/bootstrap/ /usr/local/bin/
}

setup_sudo
basic_apt
setup_git
setup_zsh
install_vim
set_config
install_dropbox
install_1password
install_vault
install_terraform
install_gcp
install_golang