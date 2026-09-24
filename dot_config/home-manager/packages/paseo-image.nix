# paseo を上流が配布する arm64 コンテナイメージから組む。
#
# 上流の nix パッケージ（nix/package.nix）はモノレポ全体を buildNpmPackage に
# かけるため、Pi 4 では 30〜60 分・RSS 3.7GB を要する。一方その成果物は
# ghcr.io/getpaseo/paseo のイメージとして既に配布されているので、そちらを
# 展開して使うことでビルドを回避する。参照先は paseo-image.json に固定し、
# packages/update-paseo-image.sh が書き換える。
{ lib
, stdenv
, dockerTools
, nodejs_22
, makeWrapper
, jq
}:

let
  spec = builtins.fromJSON (builtins.readFile ./paseo-image.json);

  image = dockerTools.pullImage {
    imageName = "ghcr.io/getpaseo/paseo";
    imageDigest = spec.imageDigest;
    hash = spec.hash;
    finalImageName = "paseo";
    finalImageTag = spec.version;
    os = "linux";
    arch = "arm64";
  };
in
stdenv.mkDerivation {
  pname = "paseo";
  version = spec.version;

  src = image;

  nativeBuildInputs = [ makeWrapper jq ];

  # pullImage の出力はイメージ全体の tar。manifest.json が列挙する順に
  # レイヤを重ねて最終的なファイルシステムを再構成する。レイヤのパス形式は
  # skopeo のバージョンで変わるため、manifest.json の Layers を正として読む。
  unpackPhase = ''
    runHook preUnpack

    mkdir -p image rootfs
    tar -xf "$src" -C image

    for layer in $(jq -r '.[0].Layers[]' image/manifest.json); do
      tar -xf "image/$layer" -C rootfs \
        --exclude='dev/*' --exclude='proc/*' --exclude='sys/*' \
        --no-same-owner --no-same-permissions
    done

    test -d rootfs/usr/local/lib/node_modules/@getpaseo/cli \
      || { echo "paseo の node_modules が見つからない"; exit 1; }

    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp -r rootfs/usr/local/lib/node_modules "$out/lib/node_modules"

    # イメージ内の /usr/local/bin/paseo は相対 symlink なので、実体である
    # cli の dist/index.js を node で直接起動するラッパーに置き換える。
    # shebang は `env -S node --disable-warning=DEP0040` で PATH の node に
    # 依存するため、ラッパー側で node を固定する。
    mkdir -p "$out/bin"
    makeWrapper ${nodejs_22}/bin/node "$out/bin/paseo" \
      --add-flags "--disable-warning=DEP0040" \
      --add-flags "$out/lib/node_modules/@getpaseo/cli/dist/index.js" \
      --prefix PATH : ${lib.makeBinPath [ nodejs_22 ]}

    runHook postInstall
  '';

  meta = {
    description = "Paseo daemon and CLI, repackaged from the upstream arm64 container image";
    homepage = "https://github.com/getpaseo/paseo";
    platforms = [ "aarch64-linux" ];
    mainProgram = "paseo";
  };
}
