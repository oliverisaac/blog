---
tags:
  - kubernetes
  - k3s
  - operating-systems
  - scripts
---
> [!note]
> This post is part of my [[7 Days Of Kubernetes]] where I explore setting up [a cheap MiniPC](https://amzn.to/42tenCq) as a single-node Kubernetes cluster using k3s.


I recently picked up a [MiniPC](https://amzn.to/42tenCq) to run as a home server. With bit of effort I was able to get Kubernetes up and running using [k3s](https://k3s.io/). This post will briefly explore how I did this.

## Prep Work

Before i started, I did quite a bit of reading about how to best set up k3s and the various options. I ended up going with a very basic install on Debian as that seemed like the most stable option.

Do note that I'll just be setting up a single node as I figured I could run everything I want on a single node with 8 cores / 16 GB of RAM.

### Decide on a Distro

There are two big things we need to decide: which OS do we want to run and which micro-kubernetes distribution do we want to run? 

#### Selecting an OS

My main options for an OS were:

- Rocky Linux
- Arch Linux
- Ubuntu
- Debian

Let's quickly explore these options:

##### Rocky Linux

Rocky linux is the OS I use in my day-job. Consequently it would be nice to use the same OS at home and at work. On the other hand, it's nice to have a chance to learn different tools. In addition, there is not years of documentation available for Rocky like there are for others. 

##### Arch Linux

Arch linux was an exciting option to choose because I haven't had a good chance to set up and use arch yet. However, the goal for my project was to get stuff shipping quickly and I didn't want other operating system bits to get in my way. I'll pick up arch some other time but not today.

##### Ubuntu

Historically I've run home servers using old laptops and select [Xubuntu](https://xubuntu.org/), an Ubuntu distro using the lightweight XFCE desktop manager. This tends to be a good balance between ease of use and resource consumption. 

However this time we're going fully headless with our server, so we don't need to the benefits of a desktop manager. When searching the web, I found people noting that there was some instability with Ubuntu compared to base Debian. Which brings us to...

##### Debian

Debian was selected primarily for its rock solid stability. I want to spend my time writing cool utilities or otherwise focusing on things above the OS layer and Debian should support me in that.

In addition, Debian has been around for a long time so there is extensive documentation available when I do discover an edge case.

One downside with Debian is that its stability is at the sacrifice of packages being available with bleeding edge versions. I didn't realize this would impact me, but the version of Golang that ships for Debian is 1.19, which is much older than I'd like. I ended up installing Golang using the official methods anyway so it worked out fine.

#### Selecting a Micro-Kubernetes Distribution

There are several micro-kubernetes distributions available:
- microk8s
- k0s
- minikube
- k3s

My research showed that k3s and k0s both used the fewest resources which is important for running a single node kubernetes deployment. A found some pages that claimed that k3s used slightly less memory so I chose to go with k3s.

## Install the OS

I followed the usual process for imaging a device with Linux. Though one unique twist is that I used my Android phone to build the USB rather Rufus or some other utility.

To do this, I download the ["Complete Installation" copy of Debian](https://www.debian.org/CD/) to my phone and then used [EtchDroid](https://etchdroid.app/) to write the ISO to my USB. 

I ran into network configuration issues because the WiFi on the miniPC I bought doesn't work on Linux. When I skipped configuration Debian did not default to DHCP for Ethernet and then I couldn't talk to the miniPC once I plugged it into my router. To work around this, I used Network Sharing on my Mac to get an Ethernet cable hooked up to the box while it was also attached to a display. This let me go through the GUI setup process and finalize the install.

## First Boot Configuration

There are quite a few things I like on a server and my fresh install of Debian had none of them. Below is a script logging all the little tweaks I made:

```bash
#!/usr/bin/env bash

set -x
set -eEuo pipefail

# Instlal Essential Packages
packages_to_install=(
  neovim
  curl
  sudo
  avahi-daemon # for multicast dns
  tree
  jq
  gpg
  git
  snapd
  fzf
  zoxide
  bsdmainutils
)

apt-get install -y "${packages_to_install[@]}"

## Add my user to sudo
usermod -aG sudo oisaac

cat >/etc/profile.d/kubernetes.sh <<'EOF'
alias k=kubectl
alias kns=kubens
alias kctx=kubectx
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
EOF

cat >/etc/profile.d/vim.sh <<'EOF'
set -o vi
export EDITOR=vim
EOF

cat >/etc/profile.d/shell-config.sh <<'EOF'
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=10000
export HISTFILESIZE=10000
EOF

cat >/etc/profile.d/aliases.sh <<'EOF'
alias ls='ls --color=auto'
alias ll='ls --color=auto -latr'
alias grep='grep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn,.idea,.tox,.history}'
alias vim='vim -p'
eval "$(zoxide init bash)"
EOF

# install helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg >/dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
```

I also copied over my SSH keys and disabled password-based logins. 

## Install k3s

Finally we're ready to install k3s! I followed the k3s.io setup directions and use their "pipe to shell" install:

```bash
curl -sfL https://get.k3s.io | sh -
```

After a minute or so I was able to use `kubectl get nodes` and my node was present!

## What's next?

Next up we'll set up observability within our k3s cluster. This is important so we can monitor resource utilization as we add services. Read about this in [[Day 2b - Observability with Grafana and VictoriaMetrics]]