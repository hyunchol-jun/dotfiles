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
This repo also houses nix config for mac. Install it by either:
`darwin-rebuild switch --flake $(readlink -f ~/.config/nix/flake.nix)#mini`

or

`nix run nix-darwin --extra-experimental-features "nix-command flakes" -- switch --flake $(readlink -f ~/.config/nix)#mini`

Nix update
`nix flake update`
