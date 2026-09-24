{ lib
, dockerTools
}:

let
  spec = builtins.fromJSON (builtins.readFile ./paseo-image.json);
in
dockerTools.pullImage {
  imageName = "ghcr.io/getpaseo/paseo";
  imageDigest = spec.imageDigest;
  hash = spec.hash;
  finalImageName = "paseo";
  finalImageTag = spec.version;
  os = "linux";
  arch = "arm64";
}
