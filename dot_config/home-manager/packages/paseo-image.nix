# paseo を上流が配布するコンテナイメージ（linux/amd64・linux/arm64）から組む。
#
# 上流の nix パッケージ（nix/package.nix）はモノレポ全体を buildNpmPackage に
# かけるため、Pi 4 では 30〜60 分・RSS 3.7GB を要し、x86_64 でも 15 分以上かかる
# （0.9.2 では成果物から server の exports.js が抜け、起動すらできなかった）。一方その成果物は
# ghcr.io/getpaseo/paseo のイメージとして既に配布されているので、そちらを
# 展開して使うことでビルドを回避する。参照先は paseo-image.json に固定し、
# packages/update-paseo-image.sh が書き換える。イメージの digest と FOD ハッシュは
# アーキテクチャごとに異なるため、サイドカーは images.<system> の下に分けて持つ。
{ lib
, stdenv
, dockerTools
, nodejs_22
, makeWrapper
, jq
, autoPatchelfHook
}:

let
  spec = builtins.fromJSON (builtins.readFile ./paseo-image.json);
  system = stdenv.hostPlatform.system;

  # nix の system 名 -> OCI のアーキテクチャ名と、同梱 prebuilds のディレクトリ名。
  # otherPrebuilds は当該環境で解決できない（＝削除する）側の prebuilds。
  archs = {
    aarch64-linux = { oci = "arm64"; otherPrebuilds = "linux-x64"; };
    x86_64-linux = { oci = "amd64"; otherPrebuilds = "linux-arm64"; };
  };
  archFor = sys: archs.${sys} or (throw "paseo-image: ${sys} は未対応");
  arch = archFor system;

  # 指定 system 向けのイメージを取得する。pullImage の出力（イメージ tar）は
  # 取得するアーキテクチャだけで決まり、ビルドするマシンの system には依らない。
  # update-paseo-image.sh が passthru 経由で呼び、手元のマシンのまま全アーキテクチャの
  # FOD ハッシュを得るのに使う。
  imageFor = sys: dockerTools.pullImage {
    imageName = "ghcr.io/getpaseo/paseo";
    imageDigest = spec.images.${sys}.imageDigest;
    hash = spec.images.${sys}.hash;
    finalImageName = "paseo";
    finalImageTag = spec.version;
    os = "linux";
    arch = (archFor sys).oci;
  };
in
stdenv.mkDerivation {
  pname = "paseo";
  version = spec.version;

  src = imageFor system;

  nativeBuildInputs = [ makeWrapper jq autoPatchelfHook ];

  # prebuilds は Debian でリンクされているため、nix の動的リンカとクロージャ内の
  # ライブラリに向け直す。node-pty は libstdc++ / libgcc_s を要求する。
  # sherpa-onnx は加えて同梱の libsherpa-onnx-c-api.so / libonnxruntime.so を要求するが、
  # これらは同じディレクトリにあり RUNPATH=$ORIGIN で解決される。
  buildInputs = [
    stdenv.cc.cc.lib
  ];

  # autoPatchelfIgnoreMissingDeps は使わない。解決できない依存はビルドを止めるべきで、
  # 黙って通すと上流が新しいライブラリを要求し始めたときに実行時まで判明しない。
  # 当該環境で解決できない他アーキテクチャの prebuilds は installPhase で削除する
  # （darwin / win32 の prebuilds は ELF ではないため autoPatchelf は元から無視する）。

  # cli/bin/paseo の shebang は `#!/usr/bin/env -S node --disable-warning=DEP0040` で、
  # patchShebangs がこの形を壊して node を落とす（env: unrecognized option になる）。
  # $out/bin/paseo は makeWrapper 製なので patch は不要。
  dontPatchShebangs = true;

  # pullImage の出力はイメージ全体の tar。manifest.json が列挙する順に
  # レイヤを重ねて最終的なファイルシステムを再構成する。レイヤのパス形式は
  # skopeo のバージョンで変わるため、manifest.json の Layers を正として読む。
  unpackPhase = ''
    runHook preUnpack

    mkdir -p image rootfs
    tar -xf "$src" -C image

    # 必要なのは node_modules だけ。サブツリーを名指しで取り出すことで、
    # tar の --exclude（既定で非アンカーのため深い階層の dev/ proc/ sys/ にも当たり、
    # 依存パッケージのファイルを静かに落とす）を使わずに済み、展開量も減る。
    for layer in $(jq -r '.[0].Layers[]' image/manifest.json); do
      tar -xf "image/$layer" -C rootfs \
        --no-same-owner --no-same-permissions \
        usr/local/lib/node_modules 2>/dev/null || true
    done

    # OverlayFS の whiteout（後段レイヤが前段のファイルを削除した印）を反映する。
    # 現在のイメージでは node_modules 配下に whiteout は無いが、上流が prune を
    # 入れた場合に削除済みファイルが復活するのを防ぐ。
    find rootfs -name '.wh.*' -printf '%h\0%f\0' | while IFS= read -r -d "" dir && IFS= read -r -d "" marker; do
      rm -rf "$dir/''${marker#.wh.}"
      rm -f "$dir/$marker"
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

    # 当該環境で解決できない ELF（他アーキテクチャの prebuilds）を削除する。
    # これで autoPatchelf が扱う ELF は自アーキテクチャのものだけになり、
    # 解決漏れを無視する設定が不要になる。
    find "$out/lib/node_modules" -type d -name '${arch.otherPrebuilds}' -prune -exec rm -rf {} +

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

  passthru = { inherit imageFor; };

  meta = {
    description = "Paseo daemon and CLI, repackaged from the upstream container image";
    homepage = "https://github.com/getpaseo/paseo";
    platforms = builtins.attrNames archs;
    mainProgram = "paseo";
  };
}
