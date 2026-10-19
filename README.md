# Droidloom on NixOS

Run Android applications in native Wayland windows on NixOS.

## Overview

Droidloom weaves Android into Linux, running Android apps in separate Wayland windows with:
- Real Android APIs (not an emulator)
- GPU acceleration via Mesa/Vulkan
- Native desktop integration (clipboard, notifications, app launcher)
- ARM64 app support on x86_64 via translation (Digitalis/Berberis)

## Hardware Requirements

- **x86_64** architecture
- **AMD or Intel GPU** (NVIDIA is not officially supported)
- **20+ GiB free disk space** for packages and Android data
- **Wayland compositor** (Hyprland, Sway, GNOME, KDE Plasma, etc.)
- **systemd user session** with polkit for initial setup

## Installation

### Option 1: NixOS Module (Recommended)

Add to your `configuration.nix` or flake:

```nix
{ config, pkgs, ... }:
{
  imports = [ ./droidloom-module.nix ];  # or from flake

  services.droidloom = {
    enable = true;
    user = "yourusername";  # User with Wayland session
    uid = 1000;
    graphics.enable = true;
    audio.enable = true;
    adb = true;
    autoStart = true;
    mode = "desktop";
    dpi = 160;
  };

  # Required for Wayland + GPU
  hardware.opengl.enable = true;
  services.pipewire = {
    enable = true;
    wireplumber.enable = true;
  };

  # User must be in video/render/input groups
  users.users.yourusername = {
    isNormalUser = true;
    extraGroups = [ "video" "render" "input" "wheel" ];
  };
}
```

Rebuild: `sudo nixos-rebuild switch --flake .#your-host`

### Option 2: Flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    droidloom.url = "github:yourname/droidloom-nixos";  # or local path
  };

  outputs = { self, nixpkgs, droidloom, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        droidloom.nixosModules.droidloom
        ({ config, pkgs, ... }: {
          services.droidloom = {
            enable = true;
            user = "yourusername";
            uid = 1000;
            graphics.enable = true;
            audio.enable = true;
            adb = true;
            autoStart = true;
          };
        })
      ];
    };
  };
}
```

## First-Time Setup

After rebuilding and rebooting into the new configuration:

1. **Start Droidloom** (requires admin auth on first run):
   ```bash
   droidloomctl start
   ```
   Approve the polkit prompt in your desktop authentication agent.

2. **Verify it's running**:
   ```bash
   droidloomctl status
   droidloomctl applications
   ```

3. **Launch a built-in app**:
   ```bash
   droidloomctl launch com.android.settings
   ```

4. **Set display density** (optional, persists):
   ```bash
   droidloomctl dpi 160
   ```

## Installing APKs

```bash
# Start Droidloom first
droidloomctl start

# Install a standalone APK
droidloomctl install ~/Downloads/app.apk

# Launch installed app
droidloomctl applications  # Find package name
droidloomctl launch com.whatsapp
```

For apps needing explicit activity:
```bash
droidloomctl launch com.halfbrick.fruitninjafree \
  --component com.halfbrick.fruitninjafree/com.halfbrick.mortar.MortarGameLauncherActivity
```

## ADB Access

If `services.droidloom.adb = true`:

```bash
# List devices
adb devices -l
# Shows: 10.177.0.2:5555 model:Droidloom device:droidloom

# Shell access
adb -s device:droidloom shell

# Install via ADB
adb -s device:droidloom install app.apk
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Droidloom |
| `user` | string | - | Desktop user name |
| `uid` | int | 1000 | User UID |
| `mode` | enum | `"desktop"` | Window mode: `desktop` or `mobile` |
| `dpi` | int | `160` | Android display density |
| `graphics.enable` | bool | `true` | GPU acceleration |
| `graphics.device` | string | null | Specific render node (auto-detect) |
| `graphics.allowNvidia` | bool | `false` | Allow NVIDIA (unsupported) |
| `audio.enable` | bool | `true` | PipeWire audio |
| `audio.sessionManager` | enum | `"wireplumber"` | Session manager |
| `adb` | bool | `true` | Enable ADB |
| `gapps` | bool | `false` | Google Apps (needs gapps package) |
| `autoStart` | bool | `true` | Start with graphical session |
| `dataDir` | path | `/var/lib/droidloom/users/<uid>/host-storage` | Android data directory |
| `extraEnvironment` | attrset | `{}` | Extra env vars for droidloom-wayland |

## Useful Commands

```bash
# Lifecycle
droidloomctl start
droidloomctl stop
droidloomctl restart

# Apps
droidloomctl applications
droidloomctl launch <package> [--component <activity>] [--resolution WxH]
droidloomctl install <apk-path> [--user <id>]

# Configuration
droidloomctl dpi <value>
droidloomctl mode [desktop|mobile]

# Diagnostics
droidloomctl status
droidloomctl logs [-n <lines>] [<package>]
droidloomctl crashes [<package>]
droidloomctl --json crashes > crash-report.json

# System logs
journalctl --user -u droidloom.service -n 100
journalctl -b -u droidloomd.service -n 200
```

## Known Limitations

- **NVIDIA GPUs**: Not validated, may not render correctly
- **ARM32 apps**: Unsupported
- **ARM64 apps**: Experimental translation, compatibility varies
- **Split APKs** (`.apkm`, `.apks`, `.xapk`): Not supported
- **Google Play Services**: Requires separate gapps integration
- **Manual startup**: Apps don't auto-start stopped runtime

## Building from Source

The NixOS module builds Droidloom from source using the upstream build process:

```bash
# Build locally (for development)
nix build .#droidloom

# Or build individual outputs
nix build .#droidloom-runtime
nix build .#droidloom-image
```

The build uses `cargo run -p droidloom-package -- build` inside a derivation, which:
1. Compiles all Rust host components
2. Builds modified Android components (SurfaceFlinger, Audio, etc.)
3. Assembles the Android system image
4. Produces the runtime and image directory trees

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    NixOS Host                               │
├─────────────────────────────────────────────────────────────┤
│  systemd --user                                             │
│  ├── droidloom.service (droidloom-wayland presenter)       │
│  ├── droidloom-audio.socket                                 │
│  ├── droidloom-applications.service                         │
│  └── droidloom-recovery.service                             │
├─────────────────────────────────────────────────────────────┤
│  systemd (system)                                           │
│  └── droidloomd.service (supervisor, namespaces, mounts)   │
├─────────────────────────────────────────────────────────────┤
│  Android Cell (shared kernel)                               │
│  ├── init → zygote → system_server → apps                  │
│  ├── binder / ashmem / sync_file (kernel modules)          │
│  └── GPU: Mesa/Vulkan → Wayland → Host compositor          │
└─────────────────────────────────────────────────────────────┘
```

## Files Created

| Path | Purpose |
|------|---------|
| `/etc/droidloom/cell.json` | Cell specification (uid, data_dir, mode, dpi) |
| `/etc/droidloom/runtime.env` | Environment for droidloom-wayland |
| `/var/lib/droidloom/users/<uid>/host-storage/data` | Android `/data` mount |
| `/var/lib/droidloom/users/<uid>/host-storage/metadata` | Android `/metadata` mount |
| `/run/droidloom/` | Runtime sockets and state |

## Troubleshooting

### "Android looks stuck"
```bash
droidloomctl wait
journalctl --user -u droidloom.service -n 100
journalctl -b -u droidloomd.service -n 200
```

### GPU not detected
```bash
# Check render nodes
ls -la /dev/dri/renderD*

# Verify Mesa/Vulkan
vulkaninfo --summary
```

### Permission denied on start
Ensure user is in `video`, `render`, `input` groups and polkit agent is running.

### ADB not connecting
```bash
# Restart ADB server
adb kill-server
droidloomctl restart
adb devices -l
```

## References

- [Upstream Repository](https://github.com/denialwm/droidloom)
- [Installation Guide](https://github.com/denialwm/droidloom/blob/main/docs/INSTALL.md)
- [Known Issues](https://github.com/denialwm/droidloom/blob/main/docs/KNOWN_ISSUES.md)
- [Desktop Integration](https://github.com/denialwm/droidloom/blob/main/docs/desktop-integration.md)
- [Building Guide](https://github.com/denialwm/droidloom/blob/main/docs/BUILDING.md)
