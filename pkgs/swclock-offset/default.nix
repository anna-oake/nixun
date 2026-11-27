{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  coreutils,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "swclock-offset";
  version = "0.3.0";

  src = fetchurl {
    url = "https://gitlab.nura.eco/postmarketOS/swclock-offset/-/archive/${finalAttrs.version}/swclock-offset-${finalAttrs.version}.tar.gz";
    hash = "sha256-d557/nD3UXGnJhFjgSsvxJ+1s7s9DLKhZmlhsZoedk8=";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  makeFlags = [
    "prefix=$(out)"
    "cachedir=/var/lib"
  ];
  installTargets = [ "bin" ];

  postInstall = ''
    for script in "$out/bin/"*; do
      wrapProgram "$script" --prefix PATH : "${lib.makeBinPath [ coreutils ]}"
    done
  '';

  meta = {
    description = "Keep system time at an offset to a read-only RTC";
    homepage = "https://gitlab.nura.eco/postmarketOS/swclock-offset";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
})
