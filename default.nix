{system ? builtins.currentSystem}: 
let
  # pin a specific nixpkgs so this works consistently for folks running different versions locally
  pkgs = import (builtins.fetchTarball {
    name = "nixos-20.03-20200528";
    url = "https://github.com/nixos/nixpkgs/archive/d55a904271f9502e9fd1290be5268ee168893dd3.tar.gz";
    sha256 = "1qakjpv1szxl9f1jfsw65ybjmcv3c0609p7hga72snjypq9bzypz";
  }) {inherit system;};

  inherit (pkgs) stdenv;
  grubDevBuild = grubPkg: pkgs.enableDebugging (grubPkg.overrideAttrs (a: {configureFlags = ["--with-platform=emu" "--target=x86_64"]; } ));

  # Build `grubPatchedSource grub_202`, f/e, to generate a Nix derivation with the source of grub_202; gdb can be pointed at this location
  grubPatchedSource = grubPkg: grubPkg.overrideDerivation (a: {
    name = "${a.name}-src";
    phases = "unpackPhase patchPhase installPhase";
    outputs = ["out"];
    installPhase = ''
      cp -av . "$out"
    '';
  });
in rec {
  inherit pkgs grubPatchedSource grubDevBuild;
  grub_202 = grubDevBuild (pkgs.callPackage ./pkgs/grub_2.02/2.0x.nix { zfsSupport = false; });
  grub_202_patched = grubDevBuild ((pkgs.callPackage ./pkgs/grub_2.02/2.0x.nix { zfsSupport = false; }).overrideAttrs (a: {patches = [./pkgs/grub_2.02/openpgp-hashed-keyid-subpacket.patch] ++ a.patches;}));
  grub_204 = grubDevBuild (pkgs.callPackage ./pkgs/grub_2.04/2.0x.nix { zfsSupport = false; });
  grub_master = grubDevBuild ((pkgs.callPackage ./pkgs/grub_2.04/2.0x.nix { zfsSupport = false; }).overrideAttrs (a: {
    name = "grub-master";
    src = builtins.fetchGit { url = "https://git.savannah.gnu.org/git/grub.git"; };
  }));
  grub_204_dja = grub_204.overrideAttrs (a: {patches = [./dja-rebase-20200528.patch];});
  grub_master_dja = grub_master.overrideAttrs (a: {patches = [./dja-rebase-20200528.patch];});

  goPgpTools = pkgs.buildGoPackage rec {
    pname = "openpgp_test_tools";
    version = "0.0.1";
    src = ./go/openpgp_test_tools;
    goDeps = ./go/openpgp_test_tools/deps.nix;
    goPackagePath = "openpgp_test_tools";
    subPackages = [ "cmd/create_key" "cmd/extract_pubkey" "cmd/sign" ];
  };

  # yes, this is a very non-binary-reproducible thing being described as a Nix derivation.
  testPrivKey = pkgs.runCommand "pgp-test-privkey.pgp" {} ''
    ${goPgpTools}/bin/create_key >"$out"
  '';

  # public key in two different formats: Written by go; written by GnuPG
  testPubKeyGo = pkgs.runCommand "pgp-test-pubkey-go.pgp" { inherit testPrivKey; } ''
    ${goPgpTools}/bin/extract_pubkey <"$testPrivKey" >"$out"
  '';

  testPubKeyGnupg = pkgs.runCommand "pgp-test-pubkey-gnupg.pgp" { inherit testPubKeyGo; } ''
    export GNUPGHOME=$PWD/gpghome
    mkdir -p "$GNUPGHOME" || exit
    ${pkgs.gnupg}/bin/gpg --import "$testPubKeyGo"
    ${pkgs.gnupg}/bin/gpg --export >"$out"
  '';

  grubCfgTextBuilder = {moduleName ? "pgp"}: ''
    insmod echo
    insmod ${moduleName}
    trust (memdisk)/pubKey
    if verify_detached (memdisk)/signedFile (memdisk)/signatureFile; then
      echo ""
      echo "==VERIFY SUCCEEDED=="
      echo ""
    else
      echo ""
      echo "==VERIFY FAILED=="
      echo ""
    fi
    exit
  '';
  grubMemdiskBuilder = {pubKey, signedFile, signatureFile}: pkgs.runCommand "grub-test.tar" {inherit pubKey signedFile signatureFile;} ''
    mkdir -p build
    cp -- "$pubKey" build/pubKey
    cp -- "$signedFile" build/signedFile
    cp -- "$signatureFile" build/signatureFile
    ${pkgs.gnutar}/bin/tar --mtime=@0 -f "$out" -C build/. -c .
  '';

  signWithGnupg = { signedFile ? ./testContent, privateKey ? testPrivKey }: pkgs.runCommand "grub.sig" { inherit signedFile privateKey; } ''
    export GNUPGHOME=$PWD/gpghome
    mkdir -p "$GNUPGHOME"
    ${pkgs.gnupg}/bin/gpg --import --batch <"$privateKey"
    ${pkgs.gnupg}/bin/gpg --output "$out" --detach-sig "$signedFile"
  '';

  signWithGo = { signedFile ? ./testContent, privateKey ? testPrivKey }: pkgs.runCommand "go.sig" { inherit signedFile privateKey; } ''
    ${goPgpTools}/bin/sign "$privateKey" <"$signedFile" >"$out"
  '';

  # Call a function with each possible test case; return a list of its results
  forEachTestCase = fn: pkgs.lib.flatten (builtins.map (grubVersion: builtins.map (pubKeyForm: builtins.map (sigForm: fn {inherit grubVersion pubKeyForm sigForm;}) sigForms) pubKeyForms) grubVersions);

  # The data used to populate those test cases:
  grubVersions = [
    {name = "GRUB_2.02_Unpatched"; grub = grub_202;         moduleName = "verify";}
    {name = "GRUB_2.02_Patched";   grub = grub_202_patched; moduleName = "verify";}
    {name = "GRUB_2.04_Unpatched"; grub = grub_204;         moduleName = "pgp";}
    {name = "GRUB_2.04_Patched";   grub = grub_204_dja;     moduleName = "pgp";}
    {name = "GRUB_master";         grub = grub_master;      moduleName = "pgp";}
    {name = "GRUB_master_Patched"; grub = grub_master_dja;  moduleName = "pgp";}
  ];
  pubKeyForms = [
    {name = "Go";    pubKey = testPubKeyGo; }
    {name = "Gnupg"; pubKey = testPubKeyGnupg; }
  ];
  sigForms = [
    {name = "Go";    sigMethod = signWithGo; }
    {name = "Gnupg"; sigMethod = signWithGnupg; }
  ];

  grubRunCmd = { grubVersion, pubKeyForm, sigForm }:
    let
      inherit (sigForm) sigMethod;
      grubCfgDir = pkgs.writeTextDir "grub.cfg" (grubCfgTextBuilder { inherit (grubVersion) moduleName; });
      grubMemdisk = grubMemdiskBuilder rec {
          inherit (pubKeyForm) pubKey;
          signedFile = ./testContent;
          signatureFile = sigMethod { inherit signedFile; };
        };
    in ''${grubVersion.grub}/bin/grub-emu --memdisk="${grubMemdisk}" --dir="${grubCfgDir}"'';

  gdbScript = {grubVersion, pubKeyForm, sigForm} @ args: pkgs.writeScript "debug-${grubVersion.name}-key${pubKeyForm.name}-sig${sigForm.name}" ''
    #!/bin/sh
    exec ${pkgs.gdb}/bin/gdb \
      --pid="$grub_pid" \
      --eval-command="directory ${grubPatchedSource grubVersion.grub}/grub-core" \
      --args ${grubRunCmd args}
  '';

  gdbScripts = forEachTestCase gdbScript;
  gdbScriptDir = pkgs.runCommand "gdb-entrypoints.d" {} ''
    mkdir -p "$out"
    ${builtins.concatStringsSep "" (map (gdbScript: ''
      ln -s -- ${gdbScript} "$out"/${gdbScript.name};
    '') gdbScripts)}
  '';

  genReportPiece = { grubVersion, pubKeyForm, sigForm }:
    pkgs.runCommand "grubTest-${grubVersion.name}-${pubKeyForm.name}-${sigForm.name}" {} ''
      ${grubRunCmd {inherit grubVersion pubKeyForm sigForm;}} | tee ./grub.out >&2
      printf '%-20s %-20s %-20s %-20s %s\n' "${grubVersion.name}" "${pubKeyForm.name}" "${sigForm.name}" "$(tr '\r' '\n' <grub.out | grep -oe '==VERIFY.*==' | tr -d '=')" "${grubVersion.grub}" >"$out"
    '';

  fullReportPieces = forEachTestCase genReportPiece;
  fullReport = pkgs.runCommand "grub-report.txt" { inherit fullReportPieces; } ''
    read -r -a fullReportPieces <<<"$fullReportPieces"
    {
      printf '%-20s %-20s %-20s %-20s %s\n' "Version" "Pubkey Format" "Sig Format" "Result" "Grub Build" "===" "===" "===" "===" "==="
      cat "''${fullReportPieces[@]}"
    } >"$out"
  '';
}
