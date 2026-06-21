# Notion CLI (ntn) は nixpkgs に無く、Rust 製のビルド済みバイナリ配布のため
# tarball を fetchurl で取得して bin に置く。Linux は static-pie のため patchelf 不要。
{ stdenvNoCC, stdenv, fetchurl }:

let
  version = "0.17.0";
  sources = {
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-3wBdObguJkxgUePErSYB978w+u8hiweLygwmDWrYDjs=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-dWVIH6ok2G5zWcN0ozywHMcmWhUIqEeluJuHdNfEG5k=";
    };
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-mNj88+traB1yKPINxmGppTJs7X96Laz2+f5vkKVMJkc=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-cqUq0rb5dbKdCP7KLYIRxaNdUtohT6E/6FkYYL5PbQg=";
    };
  };
  plat = sources.${stdenv.hostPlatform.system} or (throw
    "ntn: unsupported system ${stdenv.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "ntn";
  inherit version;
  src = fetchurl {
    url = "https://ntn.dev/releases/v${version}/ntn-${plat.target}.tar.gz";
    inherit (plat) hash;
  };
  sourceRoot = "ntn-${plat.target}";
  installPhase = ''
    runHook preInstall
    install -Dm0755 ntn "$out/bin/ntn"
    runHook postInstall
  '';
  meta = {
    description = "Notion CLI";
    homepage = "https://developers.notion.com/cli/get-started/overview";
    mainProgram = "ntn";
    platforms = builtins.attrNames sources;
  };
}
