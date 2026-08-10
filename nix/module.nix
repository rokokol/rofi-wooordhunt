# Home Manager module. It installs the package and nothing else: the mode names itself
# through the script protocol, so nothing has to be declared in the rofi config, and the
# key is yours to bind — `rofi-wooordhunt` is the whole command
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.rofi-wooordhunt;
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
  };

  config = lib.mkIf cfg.enable { home.packages = [ cfg.package ]; };
}
