{ fetchFromGitHub, fetchFromGitLab }:

{
  xun = fetchFromGitHub {
    owner = "xushengfeng";
    repo = "redmi_pad_se_xun_linux";
    rev = "f25fba528aa352b3706bba363c5b05444e03ebe8";
    hash = "sha256-ksOv5kp6T91M/0/hcormobDWOkXJ6ilLzZUeb0DSq7c=";
  };

  tapas = fetchFromGitHub {
    owner = "Sype0";
    repo = "pmos-tapas";
    rev = "5dee84cc5d7939a1042cf9daf2a21e67ab5c3579";
    hash = "sha256-d/MS39pr4HxhvgKN7tHzDchsDXUzKzJW8insm2SG19k=";
  };

  ath10k = fetchFromGitLab {
    owner = "kernel-firmware";
    repo = "linux-firmware";
    tag = "20261019";
    sparseCheckout = [
      "/ath10k/WCN3990/hw1.0/board-2.bin"
      "/ath10k/WCN3990/hw1.0/firmware-5.bin"
      "/ath10k/WCN3990/hw1.0/notice.txt_wlanmdsp"
      "/LICENSES/LICENSE.QualcommAtheros_ath10k"
    ];
    nonConeMode = true;
    hash = "sha256-iaL+r9Qz+q/CaTgxnWTAL279XhQmONEvMr4R8KWi+6c=";
  };

  audioreach = fetchFromGitHub {
    owner = "linux-msm";
    repo = "audioreach-topology";
    rev = "d6bb205aca5f4b8fa6b2f44cf8b5f6a081cbf037";
    hash = "sha256-J/xqKMa428ScOa/WOvoRopZpo2L70w78XRp8v7JHKRY=";
  };
}
