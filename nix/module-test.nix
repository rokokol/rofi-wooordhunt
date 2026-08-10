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
      options.home.packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
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

  on = eval {
    programs.rofi-wooordhunt = {
      enable = true;
      prompt = "🤓";
    };
  };

  off = eval { programs.rofi-wooordhunt.enable = false; };
in
{
  # Joined rather than indexed, so "installed nothing" fails the assertion instead of
  # blowing up during evaluation with an unhelpful list error
  package = lib.concatMapStringsSep " " toString on.home.packages;
  # The prompt travels with the package, so a settings change has to move the store path
  tunedPackage =
    lib.concatMapStringsSep " " toString
      (eval {
        programs.rofi-wooordhunt = {
          enable = true;
          prompt = "📖";
        };
      }).home.packages;

  offPackages = off.home.packages;
}
