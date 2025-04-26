# dotfiles
This is my dotfiles repo using [dotbot](https://github.com/anishathalye/dotbot). 
I manage the configuration files of the programs I use.
You can clone & install this repo, and all the configuration files will be in the newly installed system.

## Installation
1. clone this repository.
`$ git clone git@github.com:hyunchol-jun/dotfiles.git`
2. run install
```
$ cd dotfiles
$ ./install
```
This repo also houses nix config for mac. 
First, you'd need to install nix package manager onto your system.

```
sh <(curl -L https://nixos.org/nix/install)
```

Then:
`darwin-rebuild switch --flake $(readlink -f ~/.config/nix/flake.nix)#mini`

or

`nix run nix-darwin --extra-experimental-features "nix-command flakes" -- switch --flake $(readlink -f ~/.config/nix)#mini`

## After install
Nix update
`nix flake update`

Tmux plugin manager
1. Clone the repo
```
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```
2. Reload config file
```
# type this in terminal if tmux is already running
tmux source ~/.tmux.conf
```
