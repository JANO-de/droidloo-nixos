{ config, lib, pkgs, ... }:

let
  cfg = config.services.droidloom;
in
{
  options.services.droidloom = {
    enable = lib.mkEnableOption "Droidloom Android application runtime";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.droidloom;
      description = "Droidloom package (must provide runtime and image outputs)";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "user";
      description = "User that will run Droidloom (must have a Wayland session)";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "UID of the user";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/droidloom/users/${toString cfg.uid}/host-storage";
      description = "Directory for Android data (mounted at /data in Android)";
    };

    mode = lib.mkOption {
      type = lib.types.enum [ "desktop" "mobile" ];
      default = "desktop";
      description = "Window mode for Android apps";
    };

    dpi = lib.mkOption {
      type = lib.types.int;
      default = 160;
      description = "Android display density (DPI)";
    };

    graphics = {
      enable = lib.mkEnableOption "Enable GPU acceleration for Droidloom";
      device = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Specific render node (e.g. /dev/dri/renderD128). Auto-detected if null";
      };
      allowNvidia = lib.mkEnableOption "Allow NVIDIA GPU (not officially supported, may not work)";
    };

    audio = {
      enable = lib.mkEnableOption "Enable audio via PipeWire";
      sessionManager = lib.mkOption {
        type = lib.types.enum [ "wireplumber" "pipewire-media-session" ];
        default = "wireplumber";
        description = "PipeWire session manager to use";
      };
    };

    adb = lib.mkEnableOption "Enable ADB access to the Android instance";

    gapps = lib.mkEnableOption "Enable Google Apps (requires separate gapps package)";

    autoStart = lib.mkEnableOption "Start Droidloom automatically with graphical session";

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables for droidloom-wayland";
    };
  };

  config = lib.mkIf cfg.enable {
    # Assertion for NVIDIA warning
    _ = lib.assertMsg (cfg.graphics.allowNvidia || !lib.hasPrefix "nvidia" (cfg.graphics.device or ""))
      "NVIDIA rendering is not validated for Droidloom. Set graphics.allowNvidia = true to override.";

    # Required kernel modules
    boot.kernelModules = lib.mkUnique (cfg.boot.kernelModules ++ [
      "binder_linux"
      "ashmem_linux"
      "sync_file"
      "dma_heap"
      "ion"
    ]);

    # Required system packages
    environment.systemPackages = with pkgs; [
      android-tools
      (cfg.package.runtime)
      (cfg.package.image)
    ] ++ lib.optional cfg.audio.enable pipewire ++
    lib.optional (cfg.audio.sessionManager == "wireplumber") wireplumber ++
    lib.optional (cfg.audio.sessionManager == "pipewire-media-session") pipewire-media-session;

    # Polkit rule for setup authorization
    security.polkit.rules = lib.mkForce [
      {
        action = "org.droidloom.setup";
        description = "Set up Droidloom for this desktop user";
        message = "Administrator access is needed to write Droidloom configuration in /etc/droidloom, authorize its service, and create Android data files in /var/lib/droidloom.";
        defaults = {
          allow_any = "no";
          allow_inactive = "no";
          allow_active = "auth_admin";
        };
        annotate = {
          "org.freedesktop.policykit.exec.path" = "${cfg.package.runtime}/lib/droidloom/droidloom-package-helper";
        };
      }
    ];

    # Systemd service for droidloomd (system service)
    systemd.services.droidloomd = {
      description = "Droidloom Android cell lifecycle daemon";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "main";
        ExecStart = "${cfg.package.runtime}/bin/droidloom-supervisor";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStartSec = 160;
        TimeoutStopSec = 160;
      };
    };

    # User service for droidloom-wayland (presenter)
    systemd.user.services.droidloom = {
      description = "Droidloom Android application runtime";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session-pre.target" "droidloom-audio.socket" ];
      wants = [ "droidloom-applications.service" "droidloom-audio.socket" ];
      path = [ cfg.package.runtime ];
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "main";
        EnvironmentFile = "/etc/droidloom/runtime.env";
        Environment = {
          DROIDLOOM_MODE = cfg.mode;
        };
        ExecStartPre = "systemctl start droidloomd.service";
        ExecStart = "${cfg.package.runtime}/bin/droidloom-wayland";
        ExecStartPost = "${cfg.package.runtime}/bin/droidloomctl start --cell";
        ExecStopPost = [
          "-${cfg.package.runtime}/bin/droidloomctl stop --cell"
          "systemctl stop droidloomd.service"
        ];
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStartSec = 150;
        TimeoutStopSec = 150;
      };
    };

    # Audio socket service
    systemd.user.services.droidloom-audio = {
      description = "Droidloom audio socket";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package.runtime}/bin/droidloom-audio";
      };
    };

    systemd.user.sockets.droidloom-audio = {
      description = "Droidloom audio socket";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "%t/droidloom/audio.sock";
        SocketMode = "0660";
      };
    };

    # Applications service
    systemd.user.services.droidloom-applications = {
      description = "Droidloom application catalog";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package.runtime}/bin/droidloom-applications";
      };
    };

    # Recovery service
    systemd.user.services.droidloom-recovery = {
      description = "Droidloom event-driven recovery";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package.runtime}/bin/droidloom-recovery";
        Restart = "on-failure";
        RestartSec = 5;
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };
    };

    # Enable user services
    systemd.user.defaults.droidloom = {
      enable = cfg.autoStart;
      wantedBy = [ "graphical-session.target" ];
    };

    systemd.user.defaults.droidloom-audio.socket = {
      enable = cfg.audio.enable;
    };

    systemd.user.defaults.droidloom-applications = {
      enable = cfg.autoStart;
    };

    systemd.user.defaults.droidloom-recovery = {
      enable = cfg.autoStart;
    };

    # Create required directories and configuration
    users.users.${cfg.user} = lib.mkIf (cfg.user != "") {
      extraGroups = [ "video" "render" "input" ];
    };

    # Runtime environment file
    environment.etc."droidloom/runtime.env".text = ''
      DROIDLOOM_DATA_DIR=${cfg.dataDir}
      DROIDLOOM_DPI=${toString cfg.dpi}
      ${lib.concatStringsSep "\n" (lib.attrValues cfg.extraEnvironment)}
    '';

    # Cell specification
    environment.etc."droidloom/cell.json".text = builtins.toJSON {
      version = 1;
      data_dir = cfg.dataDir;
      uid = cfg.uid;
      mode = cfg.mode;
      dpi = cfg.dpi;
      graphics = {
        device = cfg.graphics.device;
      };
      audio = {
        enable = cfg.audio.enable;
        session_manager = cfg.audio.sessionManager;
      };
      adb = cfg.adb;
      gapps = cfg.gapps;
    };

    # Setup required directories with correct permissions
    systemd.tmpfiles.rules = [
      "d /etc/droidloom 0755 root root -"
      "d ${cfg.dataDir} 0700 root root -"
      "d ${cfg.dataDir}/data 0700 root root -"
      "d ${cfg.dataDir}/metadata 0700 root root -"
      "d /run/droidloom 0755 ${cfg.user} ${cfg.user} -"
      "L+ /var/lib/droidloom - - - - /run/droidloom"
    ];

    # Make droidloomctl available in PATH for the user
    programs.bash.shellInit = ''
      export PATH="${cfg.package.runtime}/bin:${cfg.package.image}/bin:$PATH"
      export XDG_DATA_DIRS="${cfg.package.runtime}/share:${cfg.package.image}/share:$XDG_DATA_DIRS"
    '' + lib.optionalString cfg.adb ''
      export ANDROID_SERIAL="device:droidloom"
    '';

    # Documentation
    services.droidloom.documentation = {
      enable = true;
      description = ''
        Droidloom is installed. Usage:

        1. First-time setup (requires admin):
           droidloomctl start

        2. List available apps:
           droidloomctl applications

        3. Launch an app:
           droidloomctl launch com.android.settings

        4. Install an APK:
           droidloomctl install /path/to/app.apk

        5. Set DPI (persists):
           droidloomctl dpi 160

        ADB access (if enabled):
           adb -s device:droidloom shell
           adb -s device:droidloom install app.apk

        Logs and diagnostics:
           droidloomctl logs -n 500
           droidloomctl crashes com.whatsapp
           journalctl --user -u droidloom.service -n 100
           journalctl -b -u droidloomd.service -n 200
      '';
    };
  };
}