# Home Manager module. Enabling it is meant to be enough: the key is bound and the
# modi names itself, so nothing has to be declared in the rofi config
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.rofi-wooordhunt;
  exe = lib.getExe cfg.package;
  mod = cfg.hyprland.modifier;
in
{
  options.programs.rofi-wooordhunt = {
    enable = lib.mkEnableOption "the wooordhunt.ru dictionary as a rofi mode";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.rofi-wooordhunt.override {
        inherit (cfg)
          prompt
          copyCommand
          wrapWidth
          headWidth
          timeout
          ;
      };
      defaultText = lib.literalExpression "rofi-wooordhunt carrying the settings below";
      description = "The package to install; it carries its own settings";
    };

    prompt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "🤓";
      description = ''
        What rofi shows as the mode name. The modi sets it through the script
        protocol, so no `display-<mode>` line is needed in the rofi config
      '';
    };

    copyCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "xclip -selection clipboard";
      description = "Command fed the picked entry on stdin. Defaults to `wl-copy`";
    };

    wrapWidth = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 54;
      description = ''
        Width the indented hint lines wrap at. rofi rows are single-line, so the
        wrapping is ours and has to match the window width — widen both this and
        `headWidth` for a wider window
      '';
    };

    headWidth = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 58;
      description = "Width the word line may reach before its gloss drops onto hint lines below";
    };

    timeout = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 5;
      description = "Per-request timeout in seconds handed to curl";
    };

    modeName = lib.mkOption {
      type = lib.types.str;
      default = "dictionary";
      description = "Name the mode is registered and shown under in `rofi -show`";
    };

    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = ''rofi -show ${cfg.modeName} -modi "${cfg.modeName}:${exe}"'';
      description = "The rofi invocation, for binding it somewhere this module does not reach";
    };

    hyprland = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.wayland.windowManager.hyprland.enable;
        defaultText = lib.literalExpression "config.wayland.windowManager.hyprland.enable";
        description = "Bind the key that opens the dictionary";
      };

      modifier = lib.mkOption {
        type = lib.types.str;
        default = "SUPER";
        description = ''
          Modifier for the default binding, spelled out rather than taken from a
          hyprland variable — this line is emitted before your own config is sourced,
          so a `$mainMod` defined there does not exist yet
        '';
      };

      key = lib.mkOption {
        type = lib.types.str;
        default = "Y";
        description = "Key that opens the dictionary, together with `modifier`";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {
          bind = [ "${mod}, ${cfg.hyprland.key}, exec, ${cfg.command}" ];
        };
        defaultText = lib.literalExpression "the binding listed in the README";
        description = ''
          Merged into `wayland.windowManager.hyprland.settings`. Set to `{ }` to bind
          it yourself
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { home.packages = [ cfg.package ]; }

      (lib.mkIf cfg.hyprland.enable {
        wayland.windowManager.hyprland.settings = cfg.hyprland.settings;
      })
    ]
  );
}
