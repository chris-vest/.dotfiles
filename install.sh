#!/bin/bash
set -e
set -o pipefail

# Choose a user account to use for this installation
get_user() {
	if [ -z "${TARGET_USER-}" ]; then
		mapfile -t options < <(find /home/* -maxdepth 0 -printf "%f\\n" -type d)
		# if there is only one option just use that user
		if [ "${#options[@]}" -eq "1" ]; then
			readonly TARGET_USER="${options[0]}"
			echo "Using user account: ${TARGET_USER}"
			return
		fi

		# iterate through the user options and print them
		PS3='command -v user account should be used? '

		select opt in "${options[@]}"; do
			readonly TARGET_USER=$opt
			break
		done
	fi
}

check_is_sudo() {
	if [ "$EUID" -ne 0 ]; then
		echo "Please run as root."
		exit
	fi
}

setup_sudo() {
	# add user to sudoers
	adduser "$TARGET_USER" sudo

	# add user to systemd groups
	# then you wont need sudo to view logs and shit
	gpasswd -a "$TARGET_USER" systemd-journal
	gpasswd -a "$TARGET_USER" systemd-network

	# create docker group
	sudo groupadd docker
	sudo usermod -aG docker $TARGET_USER
	sudo gpasswd -a "$TARGET_USER" docker
	sudo - $TARGET_USER

	echo -e "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
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
		software-properties-common \
		--no-install-recommends

	# turn off translations, speed up apt update
	mkdir -p /etc/apt/apt.conf.d
	echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99translations

	sudo add-apt-repository ppa:nathan-renniewaldock/flux
	sudo add-apt-repository ppa:neovim-ppa/stable

	sudo apt update || true
	sudo apt -y upgrade

	sudo apt install -y \
		adduser \
		alsa-utils \
		automake \
		bash-completion \
		bc \
		bzip2 \
		ca-certificates \
		coreutils \
		curl \
		dnsutils \
		docker.io \
		feh \
		file \
		findutils \
		fluxgui \
		gcc \
		git \
		git-core \
		gnupg \
		gnupg2 \
		go-dep \
		grep \
		gzip \
		hostname \
		i3 \
		i3lock \
		i3status \
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
		nautilus-dropbox \
		neovim \
		net-tools \
		openvpn \
		python-dev \
		python-pip \
		python3-dev \
		python3-pip \
		python3-setuptools \
		rxvt-unicode-256color \
		scrot \
		ssh \
		strace \
		suckless-tools \
		sudo \
		tar \
		tmux \
		tree \
		tzdata \
		unzip \
		usbmuxd \
		xclip \
		xcompmgr \
		xss-lock \
		xz-utils \
		zip \
		zsh \
		--no-install-recommends

	pip3 install -U \
		awscli \
		setuptools \
		wheel

	# NeoVim bits
	pip3 install --user \
		pynvim

	pip install --user --upgrade \
		pynvim
}

zsh() {
	wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh
	sudo chsh -s `which zsh`
}

setup_git() {
	echo "Git setup"
	git config --global core.editor vim
	git config --global user.name chris-vest
	git config --global user.email hotdogsandfrenchfries@gmail.com

	# create subshell to add ssh key
	# (
	# 	ssh-add $HOME/.ssh/id_rsa
	# )
}

setup_vim() {
	# update alternatives to neovim
	sudo update-alternatives --install /usr/bin/vi vi "$(command -v nvim)" 60
	sudo update-alternatives --config vi
	sudo update-alternatives --install /usr/bin/vim vim "$(command -v nvim)" 60
	sudo update-alternatives --config vim
	sudo update-alternatives --install /usr/bin/editor editor "$(command -v nvim)" 60
	sudo update-alternatives --config editor

	cd ${HOME}/.config
	git clone --recursive https://github.com/chris-vest/.vim.git nvim
	cd nvim
	git submodule update --init
}

install_light() {
	echo "Install Light"
	mkdir -p ~/projects
	pushd ~/projects
	git clone https://github.com/haikarainen/light.git
	pushd light
	./autogen.sh
	./configure && make
	sudo make install
	popd
}

install_vault() {
	mkdir -p ~/go/src/github.com/hashicorp && cd $_
    git clone https://github.com/hashicorp/vault.git
    cd ~/go/src/github.com/hashicorp/vault
	make bootstrap
	make dev
}

install_terraform() {
	curl -o /tmp/terraform.zip https://releases.hashicorp.com/terraform/0.11.11/terraform_0.11.11_linux_amd64.zip
	pushd /tmp
	unzip /tmp/terraform.zip
	chmod u+x /tmp/terraform
	sudo mv /tmp/terraform /usr/local/bin/
	popd
}

install_vscodium() {
	curl -o /tmp/vscodium.deb https://github.com/VSCodium/vscodium/releases/download/1.34.0/vscodium_1.34.0-1558029460_amd64.deb
	sudo apt install -y /tmp/vscodium.deb
}

install_gcp() {
	# Create environment variable for correct distribution
	export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"

	# Add the Cloud SDK distribution URI as a package source
	echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

	# Import the Google Cloud Platform public key
	curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

	# Update the package list and install the Cloud SDK
	sudo apt-get update && sudo apt-get -y install google-cloud-sdk
}

# install/update golang from source
install_golang() {
	export GO_VERSION
	GO_VERSION=$(curl -sSL "https://golang.org/VERSION?m=text")
	export GOPATH="/home/$USER/go"
	# export GO_SRC=/usr/local/go
	export PATH=$PATH:/usr/local/go/bin

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
	CGO_ENABLED=0 go install -a -installsuffix cgo std
	)

	# get commandline tools
	(
	set -x
	set +e
	go get github.com/golang/lint/golint
	go get golang.org/x/tools/cmd/cover
	go get golang.org/x/review/git-codereview
	go get golang.org/x/tools/cmd/goimports
	go get golang.org/x/tools/cmd/gorename
	go get golang.org/x/tools/cmd/guru

	go get github.com/genuinetools/amicontained
	go get github.com/genuinetools/apk-file
	go get github.com/genuinetools/audit
	go get github.com/genuinetools/bpfd
	go get github.com/genuinetools/bpfps
	go get github.com/genuinetools/certok
	go get github.com/genuinetools/netns
	go get github.com/genuinetools/pepper
	go get github.com/genuinetools/reg
	go get github.com/genuinetools/udict
	go get github.com/genuinetools/weather

	go get github.com/axw/gocov/gocov
	go get honnef.co/go/tools/cmd/staticcheck

	# get dependencies for vscode-go
	go get -u -v github.com/ramya-rao-a/go-outline
	go get -u -v github.com/acroca/go-symbols
	go get -u -v github.com/mdempsky/gocode
	go get -u -v github.com/rogpeppe/godef
	go get -u -v golang.org/x/tools/cmd/godoc
	go get -u -v github.com/zmb3/gogetdoc
	go get -u -v golang.org/x/lint/golint
	go get -u -v github.com/fatih/gomodifytags
	go get -u -v golang.org/x/tools/cmd/gorename
	go get -u -v sourcegraph.com/sqs/goreturns
	go get -u -v golang.org/x/tools/cmd/goimports
	go get -u -v github.com/cweill/gotests/...
	go get -u -v golang.org/x/tools/cmd/guru
	go get -u -v github.com/josharian/impl
	go get -u -v github.com/haya14busa/goplay/cmd/goplay
	go get -u -v github.com/uudashr/gopkgs/cmd/gopkgs
	go get -u -v github.com/davidrjenni/reftools/cmd/fillstruct
	go get -u -v github.com/alecthomas/gometalinter
	curl -L https://git.io/vp6lP | sh
	gometalinter --install
	
	# Stern
	go get -u github.com/kardianos/govendor
	mkdir -p $GOPATH/src/github.com/wercker
	cd $GOPATH/src/github.com/wercker
	git clone https://github.com/wercker/stern.git && cd stern
	govendor sync
	go install

	# Tools for vimgo.
	go get github.com/jstemmer/gotags
	go get github.com/nsf/gocode
	go get github.com/rogpeppe/godef

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

# install rust
install_rust() {
	curl https://sh.rustup.rs -sSf | sh
}

set_config() {
	# add aliases for dotfiles
	# for file in $(shell find $(CURDIR) -name ".*" -not -name ".gitignore" -not -name ".git"); do
	# 	f=$(basename $file)
	# 	ln -sfn $$file $(HOME)/$f
	# done

	mkdir -p .config/dunst || :

	mkdir -p .oh-my-zsh || :

	cp -R .config/dunst ~/.config/

	cp -R .i3 ~/

	cp -R .urxvt ~/

	cp .tmux.conf ~/

	cp .Xresources ~/

	cp .oh-my-zsh/custom/themes/crystal.zsh-theme ~/.oh-my-zsh/custom/themes/crystal.zsh-theme
	cp .zshrc ~/
}

kubernetes() {
	echo "kubectl helm fluxctl kubectx kubens kubectl-aliases minikube"

	sudo snap install kubectl
	sudo snap install remmina
}

usage() {
	echo -e "install.sh\\n\\tThis script installs my basic setup for an Ubuntu laptop\\n"
	echo "Usage:"
	echo "  base                	            - setup sources & install base pkgs"
	echo "  tools		                        - bits and pieces for work"
	echo "  vscodium    		                - install vscodium"
	echo "  golang	    		                - install golang"
	echo "  rust	    		                - install golang"
	echo "  zsh	      		                    - install oh-my-zsh; change shell to ZSH"
	echo "  set_config                          - set configuration"
	echo "  nvim                                - install vim specific dotfiles; run this after set_config!"
}

main() {
	local cmd=$1

	if [[ -z "$cmd" ]]; then
		usage
		exit 1
	fi

	if [[ $cmd == "base" ]]; then
		check_is_sudo
		get_user
		setup_git
		basic_apt
		setup_sudo
	elif [[ $cmd == "tools" ]]; then
		install_light
		# install_vault
		install_terraform
		install_gcp
		kubernetes
	elif [[ $cmd == "vscodium" ]]; then
		install_vscodium
	elif [[ $cmd == "golang" ]]; then
		install_golang "$2"
	elif [[ $cmd == "rust" ]]; then
		install_rust
	elif [[ $cmd == "zsh" ]]; then
		zsh
	elif [[ $cmd == "set_config" ]]; then
		set_config
	elif [[ $cmd == "nvim" ]]; then
		setup_vim
	else
		usage
	fi
}

main "$@"
