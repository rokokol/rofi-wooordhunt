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
      launcher = builtins.path {
        name = "rofi-wooordhunt.sh";
        path = ./rofi-wooordhunt.sh;
      };
      modi = builtins.path {
        name = "wooordhunt-modi.sh";
        path = ./wooordhunt-modi.sh;
      };
      testsDir = builtins.path {
        name = "rofi-wooordhunt-tests";
        path = ./tests;
      };
      installer = builtins.path {
        name = "install.sh";
        path = ./install.sh;
      };
      completionsDir = builtins.path {
        name = "rofi-wooordhunt-completions";
        path = ./completions;
      };
      versionFile = builtins.path {
        name = "rofi-wooordhunt-VERSION";
        path = ./VERSION;
      };
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = rofi-wooordhunt;
        rofi-wooordhunt = pkgs.callPackage ./nix/package.nix { };
      });

      # homeModules is the name the flake schema knows; homeManagerModules is what most
      # consumers still write, so both point at the same module
      homeModules.default = import ./nix/module.nix { inherit self; };
      homeManagerModules.default = self.homeModules.default;

      # For a consumer who reaches for pkgs rather than this flake's packages directly
      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system}) rofi-wooordhunt;
      };

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
                cp ${launcher} repo/rofi-wooordhunt.sh
                cp ${modi} repo/wooordhunt-modi.sh
                cp ${versionFile} repo/VERSION
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
                modi=${rofi-wooordhunt}/libexec/wooordhunt-modi
                mkdir -p pages/word
                ln -s ${testsDir}/fixtures/house.html pages/word/house
                export ROFI_WOOORDHUNT_URL="file://$PWD/pages"

                # No grep -q on a pipe: it closes the pipe early and the writer sees EPIPE
                ROFI_RETV=1 $modi house | tr '\000\037' '@|' >out
                grep -xF 'дом@info|дом' out >/dev/null
                grep -F '@message|🇺🇸: |haʊs|' out >/dev/null
                # The mode must name itself, without anything in rofi.rasi
                ROFI_RETV=0 $modi | tr '\000\037' '@|' | grep -xF '@prompt|🤓' >/dev/null
                rofi-wooordhunt --help | grep ROFI_WOOORDHUNT_COPY >/dev/null

                # The launcher has to hand rofi the modi of its own derivation, and pass
                # a query on as the initial filter — a stub rofi just prints its arguments
                mkdir -p stub
                printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' >stub/rofi
                chmod +x stub/rofi
                PATH=$PWD/stub:$PATH rofi-wooordhunt "два слова" >launched
                grep -xF "dictionary:$modi" launched >/dev/null ||
                  { echo "the launcher does not point rofi at its own modi"; exit 1; }
                grep -xF 'два слова' launched >/dev/null ||
                  { echo "the query did not reach rofi as one filter"; exit 1; }
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
              modi=${tuned}/libexec/wooordhunt-modi
              ROFI_RETV=0 $modi | tr '\000\037' '@|' | grep -xF '@prompt|📖' >/dev/null ||
                { echo "the mode does not carry the configured prompt"; exit 1; }
              # copyCommand = cat, so picking an entry lands on stdout
              ROFI_RETV=1 ROFI_INFO=дом $modi | grep -xF 'дом' >/dev/null ||
                { echo "the configured clipboard command was not used"; exit 1; }
              # The rest only shows against a live page, so here it is enough that the
              # wrapper passes it on — tests/run.sh drives the behaviour behind them
              for pair in "WRAP_WIDTH-'33'" "HEAD_WIDTH-'44'" "TIMEOUT-'9'"; do
                grep -F "ROFI_WOOORDHUNT_''${pair}}" $modi >/dev/null ||
                  { echo "the wrapper drops ROFI_WOOORDHUNT_''${pair%%-*}"; exit 1; }
              done
              # …and an unset setting leaves the script's own default as the single source of it
              if grep -q ROFI_WOOORDHUNT_PROMPT ${rofi-wooordhunt}/libexec/wooordhunt-modi; then
                echo "an unset setting still got baked in"
                exit 1
              fi
              touch $out
            '';

          # Enabling the module has to be enough to get the package, settings and all
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

                want '.package | test("rofi-wooordhunt")' "no package installed"
                # A setting rides in the package, so changing it has to move the store path
                want '.package != .tunedPackage' "the prompt does not reach the package"
                want '.offPackages == []' "the package is installed while disabled"
                touch $out
              '';

          scripts-lint =
            pkgs.runCommand "scripts-lint"
              {
                nativeBuildInputs = [
                  pkgs.shellcheck
                  pkgs.shfmt
                  pkgs.zsh
                ];
              }
              ''
                files="${launcher} ${modi} ${installer} ${testsDir}/run.sh ${testsDir}/live.sh ${testsDir}/refresh.sh ${testsDir}/distro.sh ${testsDir}/check-completions.sh ${testsDir}/stub/curl ${testsDir}/stub/fake-copy ${completionsDir}/install.sh.bash"
                # shellcheck disable=SC2086
                shellcheck $files
                # shellcheck disable=SC2086
                shfmt -d -i 2 -ci $files
                # zsh is not shellcheck's language; a parse is what can be checked
                zsh -n ${completionsDir}/install.sh.zsh

                # install.sh and its completions must not drift apart
                mkdir -p repo/tests
                cp ${installer} repo/install.sh
                cp -r ${completionsDir} repo/completions
                cp ${testsDir}/check-completions.sh repo/tests/
                bash repo/tests/check-completions.sh
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
