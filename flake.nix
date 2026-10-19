{
  description = "Droidloom NixOS integration - Run Android apps in Wayland windows";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, nixpkgs-stable, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };
        lib = pkgs.lib;

        # Droidloom package (built from source)
        droidloom = import ./droidloom.nix {
          inherit lib pkgs;
          inherit (pkgs) stdenv cargo rustPlatform meson ninja pkg-config fetchFromGitHub llvmPackages clang glslang spirv-llvm-translator bison flex android-tools erofs-utils e2fsprogs python3 yaml mako ccache mesa libdrm wayland libxkbcommon libpipewire pipewire wireplumber systemd polkit util-linux iproute2 nftables iptables rsync curl unzip zip glibc gcc git;
        };

        # NixOS module
        droidloomModule = import ./droidloom-module.nix {
          inherit lib pkgs;
        };

      in {
        packages.droidloom = droidloom;
        packages.droidloom-runtime = droidloom.runtime;
        packages.droidloom-image = droidloom.image;

        nixosModules.droidloom = droidloomModule;

        # Example NixOS configuration
        nixosConfigurations.example = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ({ config, pkgs, ... }: {
              imports = [ droidloomModule ];
              services.droidloom = {
                enable = true;
                user = "user";
                uid = 1000;
                graphics.enable = true;
                audio.enable = true;
                adb = true;
                autoStart = true;
                mode = "desktop";
                dpi = 160;
              };
              # Required for Wayland
              hardware.opengl.enable = true;
              services.pipewire = {
                enable = true;
                wireplumber.enable = true;
              };
              # User setup
              users.users.user = {
                isNormalUser = true;
                extraGroups = [ "video" "render" "input" "wheel" ];
              };
            })
          ];
        };
      });
}