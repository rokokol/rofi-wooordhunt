{
  description = "A rofi dictionary that translates both ways through wooordhunt.ru";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Each piece isolated, so a README edit doesn't rebuild anything
      modi = builtins.path {
        name = "rofi-wooordhunt.sh";
        path = ./rofi-wooordhunt.sh;
      };
      testsDir = builtins.path {
        name = "rofi-wooordhunt-tests";
        path = ./tests;
      };
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = rofi-wooordhunt;
        rofi-wooordhunt = pkgs.callPackage ./nix/package.nix { };
      });

      homeManagerModules.default = import ./nix/module.nix { inherit self; };

      checks = forAllSystems (
        pkgs:
        let
          rofi-wooordhunt = self.packages.${pkgs.stdenv.hostPlatform.system}.rofi-wooordhunt;
        in
        {
          # The behaviour suite: saved pages in, the rofi protocol out, diffed against
          # tests/golden. The stub curl is what keeps the sandbox off the network
          tests =
            pkgs.runCommand "tests"
              {
                nativeBuildInputs = with pkgs; [
                  bash
                  coreutils
                  diffutils
                  findutils
                  gawk
                  gnugrep
                  gnused
                  jq
                  pup
                ];
              }
              ''
                export HOME=$PWD
                mkdir -p repo
                cp ${modi} repo/rofi-wooordhunt.sh
                cp -r ${testsDir} repo/tests
                chmod -R +w repo
                patchShebangs repo
                bash repo/tests/run.sh
                touch $out
              '';

          # The wrapper is the whole difference between the repo and the package: it is
          # what makes curl, pup and jq reachable from a session that has none of them.
          # A file:// root stands in for the site, so the real curl still does the work
          package-smoke =
            pkgs.runCommand "package-smoke"
              {
                nativeBuildInputs = [
                  rofi-wooordhunt
                  pkgs.gnugrep
                ];
              }
              ''
                export HOME=$PWD PATH=${
                  lib.makeBinPath [
                    rofi-wooordhunt
                    pkgs.coreutils
                    pkgs.gnugrep
                  ]
                }
                mkdir -p pages/word
                ln -s ${testsDir}/fixtures/house.html pages/word/house
                export ROFI_WOOORDHUNT_URL="file://$PWD/pages"

                # No grep -q on a pipe: it closes the pipe early and the writer sees EPIPE
                ROFI_RETV=1 rofi-wooordhunt house | tr '\000\037' '@|' >out
                grep -xF 'дом@info|дом' out >/dev/null
                grep -F '@message|🇺🇸: |haʊs|' out >/dev/null
                # The mode must name itself, without anything in rofi.rasi
                ROFI_RETV=0 rofi-wooordhunt | tr '\000\037' '@|' | grep -xF '@prompt|🤓' >/dev/null
                rofi-wooordhunt --help | grep ROFI_WOOORDHUNT_COPY >/dev/null
                touch $out
              '';

          # Every setting the module exposes has to reach the script, or it is decoration
          package-settings =
            let
              tuned = rofi-wooordhunt.override {
                prompt = "📖";
                copyCommand = "cat";
                wrapWidth = 33;
                headWidth = 44;
                timeout = 9;
              };
            in
            pkgs.runCommand "package-settings" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
              export HOME=$PWD PATH=${
                lib.makeBinPath [
                  tuned
                  pkgs.coreutils
                  pkgs.gnugrep
                ]
              }
              ROFI_RETV=0 rofi-wooordhunt | tr '\000\037' '@|' | grep -xF '@prompt|📖' >/dev/null ||
                { echo "the mode does not carry the configured prompt"; exit 1; }
              # copyCommand = cat, so picking an entry lands on stdout
              ROFI_RETV=1 ROFI_INFO=дом rofi-wooordhunt | grep -xF 'дом' >/dev/null ||
                { echo "the configured clipboard command was not used"; exit 1; }
              # The rest only shows against a live page, so here it is enough that the
              # wrapper passes it on — tests/run.sh drives the behaviour behind them
              for pair in "WRAP_WIDTH-'33'" "HEAD_WIDTH-'44'" "TIMEOUT-'9'"; do
                grep -F "ROFI_WOOORDHUNT_''${pair}}" ${tuned}/bin/rofi-wooordhunt >/dev/null ||
                  { echo "the wrapper drops ROFI_WOOORDHUNT_''${pair%%-*}"; exit 1; }
              done
              # …and an unset setting leaves the script's own default as the single source of it
              if grep -q ROFI_WOOORDHUNT ${rofi-wooordhunt}/bin/rofi-wooordhunt; then
                echo "an unset setting still got baked in"
                exit 1
              fi
              touch $out
            '';

          # Enabling the module has to be enough to get the key and the package
          module-wiring =
            let
              wiring = import ./nix/module-test.nix {
                inherit lib pkgs;
                module = self.homeManagerModules.default;
              };
            in
            pkgs.runCommand "module-wiring"
              {
                nativeBuildInputs = [ pkgs.jq ];
                dump = builtins.toJSON wiring;
                passAsFile = [ "dump" ];
              }
              ''
                want() { jq -e "$1" "$dumpPath" >/dev/null || { echo "module wiring: $2"; exit 1; }; }

                want '.hyprland.bind | any(test("SUPER, Y, exec, rofi -show dictionary"))' "the dictionary is not bound"
                want '.hyprland.bind | any(test("dictionary:.*bin/rofi-wooordhunt"))' "the bind names no modi"
                want '.package | test("rofi-wooordhunt")' "no package installed"

                # Renaming the mode has to move every mention of it at once
                want '.renamedCommand | test("-show словарь -modi \"словарь:")' "the mode name did not follow"
                want '.renamedHyprland.bind | any(test("SUPER, D, exec"))' "the key did not follow"

                # …and none of it leaks into a config that did not ask for it
                want '.bareHyprland == {}' "binds appear without Hyprland"
                want '.offPackages == []' "the package is installed while disabled"
                want '.offHyprland == {}' "binds survive enable = false"
                touch $out
              '';

          scripts-lint =
            pkgs.runCommand "scripts-lint"
              {
                nativeBuildInputs = [
                  pkgs.shellcheck
                  pkgs.shfmt
                ];
              }
              ''
                files="${modi} ${testsDir}/run.sh ${testsDir}/stub/curl ${testsDir}/stub/fake-copy"
                # shellcheck disable=SC2086
                shellcheck $files
                # shellcheck disable=SC2086
                shfmt -d -i 2 -ci $files
                touch $out
              '';
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            jq
            pup
            shellcheck
            shfmt
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
