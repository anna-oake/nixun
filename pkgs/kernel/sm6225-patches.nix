{ fetchurl }:

let
  fetchPatch = name: rev: hash: {
    inherit name;
    patch = fetchurl {
      url = "https://gitlab.nura.eco/sm6225-mainline/kernels/linux-v.7.2.1/-/commit/${rev}.patch";
      inherit hash;
    };
  };
in
[
  (fetchPatch "sm6225-platform"
    "650f459de5b9eb6f4f73728fd935d34677074965"
    "sha256-xUwBU6Rv/qlTjanBFjS9fpXA4YOESYMkOWgYurrCZ2U="
  )
  (fetchPatch "sm6225-extended-support"
    "8b6545f79b5ff3e589436c0746fc3014739dc12c"
    "sha256-/yB8wIbh6cx2OZsgcf7CT30ZkI1bdDKNN+J1gJI/ucE="
  )
  (fetchPatch "sm6225-follow-up"
    "f5a976a8334c7563137352eaafe8d49a2a3b8c6a"
    "sha256-GYuy9v2ARu/JgerbVPCtsfR6rjZj0SSmOld5JJ/Febo="
  )
  (fetchPatch "sm6225-charging-and-camera"
    "e127de2a6297931b1abce1fb5b13a415163c325e"
    "sha256-f/p57nKxexG4Gun5mlc37K+I/KB1wemq8QpAbdnN5Hc="
  )
]
