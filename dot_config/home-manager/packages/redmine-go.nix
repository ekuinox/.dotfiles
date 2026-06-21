# nixpkgs に無い Go CLI を buildGoModule で自前ビルドする
{ buildGoModule, fetchFromGitHub }:

buildGoModule {
  pname = "redmine-go";
  version = "0.2.0";
  src = fetchFromGitHub {
    owner = "kqns91";
    repo = "redmine-go";
    rev = "v0.2.0";
    hash = "sha256-jrYo3ptqfHJk8r+05ndwBgg1UBJMcF4p0NNBoGjHcXM=";
  };
  vendorHash = "sha256-zFVdCFZK5uQAaIv3c8IMp/0B0sHOdV+xLjvjxZhEUto=";
  subPackages = [ "cmd/redmine" ];
}
