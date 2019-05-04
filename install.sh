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
	sudo gpasswd -a "$TARGET_USER" docker

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

	sudo add-apt-repository ppa:ubuntu-mozilla-daily/firefox-aurora
	sudo add-apt-repository ppa:nathan-renniewaldock/flux
	sudo add-apt-repository ppa:neovim-ppa/stable

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
		net-tools \
		neovim \
		openvpn \
		python-dev \
		python-pip \
		python3-dev \
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
	
	pip3 install -U \
		awscli \
		setuptools \
		wheel
}

oh_my_zsh() {
	wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh
	chsh -s `which zsh`
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
}

install_1password() {
	arm=$(dpkg --print-architecture)
	curl -o /tmp/op.zip https://cache.agilebits.com/dist/1P/op/pkg/v0.5.5/op_linux_${arm}_v0.5.5.zip
	pushd /tmp
	unzip /tmp/op.zip
	chmod u+x /tmp/op
	sudo mv /tmp/op /usr/local/bin/
	popd
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
	curl -o /tmp/vscodium.deb https://github.com/VSCodium/vscodium/releases/download/1.32.1/vscodium_1.32.1-1552067474_amd64.deb
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
	sudo apt-get update && sudo apt-get install google-cloud-sdk
}

# install/update golang from source
install_golang() {
	export GO_VERSION
	GO_VERSION=$(curl -sSL "https://golang.org/VERSION?m=text")
	export GOPATH="/home/$USER/go"
	export GO_SRC=$GOPATH/src

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
	CGO_ENABLED=0 /usr/local/go/bin/go install -a -installsuffix cgo std
	)

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

	# get dependencies for vscode-go
	usr/local/go/bin/go get -u -v github.com/ramya-rao-a/go-outline
	usr/local/go/bin/go get -u -v github.com/acroca/go-symbols
	usr/local/go/bin/go get -u -v github.com/mdempsky/gocode
	usr/local/go/bin/go get -u -v github.com/rogpeppe/godef
	usr/local/go/bin/go get -u -v golang.org/x/tools/cmd/godoc
	usr/local/go/bin/go get -u -v github.com/zmb3/gogetdoc
	usr/local/go/bin/go get -u -v golang.org/x/lint/golint
	usr/local/go/bin/go get -u -v github.com/fatih/gomodifytags
	usr/local/go/bin/go get -u -v golang.org/x/tools/cmd/gorename
	usr/local/go/bin/go get -u -v sourcegraph.com/sqs/goreturns
	usr/local/go/bin/go get -u -v golang.org/x/tools/cmd/goimports
	usr/local/go/bin/go get -u -v github.com/cweill/gotests/...
	usr/local/go/bin/go get -u -v golang.org/x/tools/cmd/guru
	usr/local/go/bin/go get -u -v github.com/josharian/impl
	usr/local/go/bin/go get -u -v github.com/haya14busa/goplay/cmd/goplay
	usr/local/go/bin/go get -u -v github.com/uudashr/gopkgs/cmd/gopkgs
	usr/local/go/bin/go get -u -v github.com/davidrjenni/reftools/cmd/fillstruct
	usr/local/go/bin/go get -u -v github.com/alecthomas/gometalinter
	curl -L https://git.io/vp6lP | sh
	gometalinter --install
	
	# Stern
	/usr/local/go/bin/go get -u github.com/kardianos/govendor
	mkdir -p $GOPATH/src/github.com/wercker
	cd $GOPATH/src/github.com/wercker
	git clone https://github.com/wercker/stern.git && cd stern
	govendor sync
	go install

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

	echo "export PATH=$PATH:/usr/local/go/bin/" >> $HOME/.bashrc
}

set_config() {
	# add aliases for dotfiles
	# for file in $(shell find $(CURDIR) -name ".*" -not -name ".gitignore" -not -name ".git"); do
	# 	f=$(basename $file)
	# 	ln -sfn $$file $(HOME)/$f
	# done

	mkdir -p .config/dunst || :
	mkdir -p .config/nvim || :
	mkdir -p .oh-my-zsh || :

	cp -R .config/ ~/

	cp -R .i3 ~/

	cp .tmux.conf ~/

	cp -R .oh-my-zsh ~/
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
	echo "  basic_apt                           - setup sources & install base pkgs"
	echo "  install_work                        - bits and pieces"
	echo "  oh_my_zsh	                        - install oh-my-zsh; change shell to ZSH"
	echo "  nvim                                - install vim specific dotfiles"
	echo "  set_config                          - set configuration"
}

main() {
	local cmd=$1

	if [[ -z "$cmd" ]]; then
		usage
		exit 1
	fi

	if [[ $cmd == "basic_apt" ]]; then
		check_is_sudo
		get_user

		setup_git
		basic_apt
		setup_sudo
	elif [[ $cmd == "install_work" ]]; then
		check_is_sudo
		install_golang "$2"
		install_1password
		install_light
		install_vault
		install_terraform
		install_gcp
		kubernetes
	elif [[ $cmd == "oh_my_zsh" ]]; then
		check_is_sudo

		oh_my_zsh
	elif [[ $cmd == "nvim" ]]; then
		#check_is_sudo
		setup_vim
	elif [[ $cmd == "set_config" ]]; then
		set_config
	else
		usage
	fi
}

main "$@"