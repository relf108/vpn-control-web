{ pkgs }:
pkgs.flutter.buildFlutterApplication {
  pname = "vpn-control-web";
  version = "0.2.0";
  src = pkgs.lib.fileset.toSource {
    root = ./.;
    fileset = pkgs.lib.fileset.unions [
      ./lib
      ./assets
      ./web
      ./test
      ./pubspec.yaml
      ./pubspec.lock
      ./analysis_options.yaml
    ];
  };
  pubspecLock = pkgs.lib.importJSON ./pubspec.lock.json;
  targetFlutterPlatform = "web";
  flutterBuildFlags = [ "--no-web-resources-cdn" ];
  doCheck = true;
  checkPhase = ''
    dart format --output=none --set-exit-if-changed lib test
    flutter analyze --no-pub
    flutter test --no-pub
  '';
  meta = {
    description = "Private Flutter web dashboard for vpn-control";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
  };
}
