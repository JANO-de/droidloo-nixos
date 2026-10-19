{ lib, pkgs, fetchFromGitHub, stdenv, cargo, rustPlatform, meson, ninja, pkg-config, llvmPackages, clang, glslang, spirv-llvm-translator, bison, flex, android-tools, erofs-utils, e2fsprogs, python3, yaml, mako, ccache, mesa, libdrm, wayland, libxkbcommon, libpipewire, pipewire, wireplumber, systemd, polkit, util-linux, iproute2, nftables, iptables, rsync, curl, unzip, zip, glibc, gcc, git, kernel }:

let
  droidloom-src = fetchFromGitHub {
    owner = "denialwm";
    repo = "droidloom";
    rev = "main";
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  # Override to use our toolchain
  cargoEnv = rustPlatform.cargoEnv.override {
    rustc = pkgs.rust-bin.stable.latest.default;
    cargo = pkgs.rust-bin.stable.latest.default;
  };

in rustPlatform.buildRustPackage rec {
  pname = "droidloom";
  version = "0.1.0";

  src = droidloom-src;

  nativeBuildInputs = [
    cargoEnv
    meson
    ninja
    pkg-config
    llvmPackages.bintools
    clang
    glslang
    spirv-llvm-translator
    bison
    flex
    android-tools
    erofs-utils
    e2fsprogs
    python3
    (python3.withPackages (ps: [ ps.pyyaml ps.mako ]))
    ccache
    git
    rsync
    curl
    unzip
    zip
  ];

  buildInputs = [
    mesa
    libdrm
    wayland
    libxkbcommon
    libpipewire
    pipewire
    systemd
    polkit
    util-linux
    iproute2
    nftables
    iptables
  ];

  # The build uses a custom cargo command that runs the package tool
  buildPhase = ''
    export CARGO_HOME=$PWD/.cargo
    export RUSTUP_HOME=$PWD/.rustup
    export DROIDLOOM_PACKAGE_TOOL=$PWD/target/release/droidloom-package
    export DROIDLOOM_SOURCE=$PWD
    export DROIDLOOM_WORK=$PWD/.work/arch
    export DROIDLOOM_JOBS=${NIX_BUILD_CORES:-4}

    # Build the package tool first
    cargo build --locked -j 1 -p droidloom-package --release

    # Run the full build
    $DROIDLOOM_PACKAGE_TOOL compile \
      --source $DROIDLOOM_SOURCE \
      --work $DROIDLOOM_WORK \
      --destination $PWD/payload \
      --jobs $DROIDLOOM_JOBS
  '';

  installPhase = ''
    mkdir -p $out/runtime $out/image
    $DROIDLOOM_PACKAGE_TOOL install-tree \
      --source $PWD/payload/runtime \
      --destination $out/runtime
    $DROIDLOOM_PACKAGE_TOOL install-tree \
      --source $PWD/payload/image \
      --destination $out/image
  '';

  # Multi-output derivation
  outputs = [ "out" "runtime" "image" ];
}