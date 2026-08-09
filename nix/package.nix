# The modi plus the tools it shells out to. rofi is deliberately NOT a runtime input:
# it comes from the running session, and pinning a second one here would shadow the
# user's own. The clipboard command is a setting rather than a dependency, so an X11
# user can point it at xclip without rebuilding the closure around wl-clipboard
{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  curl,
  findutils,
  gawk,
  gnugrep,
  gnused,
  jq,
  pup,
  wl-clipboard,
  # Baked into the wrapper rather than exported as session variables, so a change
  # lands on the next rebuild instead of the next login
  prompt ? null,
  copyCommand ? null,
  wrapWidth ? null,
  headWidth ? null,
  timeout ? null,
}:

let
  # Isolated, so editing the README or a fixture doesn't rebuild the package
  script = builtins.path {
    name = "rofi-wooordhunt.sh";
    path = ../rofi-wooordhunt.sh;
  };

  # Left out when unset, so the script's own default stays the single source of it
  setDefault =
    var: value: lib.optionalString (value != null) ''--set-default ${var} "${toString value}"'';

  runtimeInputs = [
    coreutils
    curl
    findutils
    gawk
    gnugrep
    gnused
    jq
    pup
    wl-clipboard
  ];
in

stdenvNoCC.mkDerivation {
  pname = "rofi-wooordhunt";
  version = "1.0";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall

    install -Dm755 ${script} $out/bin/rofi-wooordhunt
    patchShebangs $out/bin

    # --set-default, not --set: an override from the caller's environment still wins
    wrapProgram $out/bin/rofi-wooordhunt \
      --prefix PATH : ${lib.makeBinPath runtimeInputs} \
      ${setDefault "ROFI_WOOORDHUNT_PROMPT" prompt} \
      ${setDefault "ROFI_WOOORDHUNT_COPY" copyCommand} \
      ${setDefault "ROFI_WOOORDHUNT_WRAP_WIDTH" wrapWidth} \
      ${setDefault "ROFI_WOOORDHUNT_HEAD_WIDTH" headWidth} \
      ${setDefault "ROFI_WOOORDHUNT_TIMEOUT" timeout}

    runHook postInstall
  '';

  meta = {
    description = "A rofi dictionary that translates both ways through wooordhunt.ru";
    homepage = "https://github.com/rokokol/rofi-wooordhunt";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "rofi-wooordhunt";
  };
}
