{
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}:

stdenv.mkDerivation {
  pname = "nt36532-xun";
  version = "0.1-${kernel.modDirVersion}";
  src = ./src;

  nativeBuildInputs = kernel.moduleBuildDependencies;
  makeFlags = kernelModuleMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];
  preBuild = ''makeFlagsArray+=("M=$PWD")'';
  buildFlags = [ "modules" ];
  installTargets = [ "modules_install" ];
  installFlags = [ "INSTALL_MOD_PATH=${placeholder "out"}" ];
}
