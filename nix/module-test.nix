# Evaluates the Home Manager module against stubs for the option paths it writes to,
# so the wiring is checked without pulling home-manager in as an input. Produces the
# lines it would emit; flake.nix turns them into assertions
{
  lib,
  pkgs,
  module,
}:

let
  stubs =
    { lib, ... }:
    {
      options = {
        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        wayland.windowManager.hyprland = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          settings = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
        };
      };
    };

  eval =
    user:
    (lib.evalModules {
      modules = [
        stubs
        module
        user
      ];
      specialArgs = { inherit pkgs; };
    }).config;

  wiredUp = eval {
    wayland.windowManager.hyprland.enable = true;
    programs.rofi-wooordhunt = {
      enable = true;
      prompt = "🤓";
    };
  };

  renamed = eval {
    wayland.windowManager.hyprland.enable = true;
    programs.rofi-wooordhunt = {
      enable = true;
      modeName = "словарь";
      hyprland.key = "D";
    };
  };

  bare = eval { programs.rofi-wooordhunt.enable = true; };

  off = eval { programs.rofi-wooordhunt.enable = false; };
in
{
  hyprland = wiredUp.wayland.windowManager.hyprland.settings;
  # Joined rather than indexed, so "installed nothing" fails the assertion instead of
  # blowing up during evaluation with an unhelpful list error
  package = lib.concatMapStringsSep " " toString wiredUp.home.packages;

  renamedHyprland = renamed.wayland.windowManager.hyprland.settings;
  renamedCommand = renamed.programs.rofi-wooordhunt.command;

  bareHyprland = bare.wayland.windowManager.hyprland.settings;

  offPackages = off.home.packages;
  offHyprland = off.wayland.windowManager.hyprland.settings;
}
