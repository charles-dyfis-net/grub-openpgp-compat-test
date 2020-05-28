{system ? builtins.currentSystem}: 
let
  pkgs = import <nixos> {inherit system;};  # built/tested with the nixos-20.03 release channel on a Linux host
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

  # yes, this is a very non-binary-reproducible thing being described as a Nix derivation.
  goPgpTools = pkgs.buildGoPackage rec {
    pname = "openpgp_test_tools";
    version = "0.0.1";
    src = ./go/openpgp_test_tools;
    goDeps = ./go/openpgp_test_tools/deps.nix;
    goPackagePath = "openpgp_test_tools";
    subPackages = [ "cmd/create_key" "cmd/extract_pubkey" "cmd/sign" ];
  };

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
    ${pkgs.gnupg}/bin/gpg --import ${testPubKeyGo}
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

  grubVersions = [
    {name = "GRUB_2.02_Unpatched"; grub = grub_202;         moduleName = "verify";}
    {name = "GRUB_2.02_Patched";   grub = grub_202_patched; moduleName = "verify";}
    {name = "GRUB_2.04_Unpatched"; grub = grub_204;         moduleName = "pgp";}
  ];
  pubKeyForms = [
    {name = "Go";    pubKey = testPubKeyGo; }
    {name = "Gnupg"; pubKey = testPubKeyGnupg; }
  ];
  sigForms = [
    {name = "Go";    sigMethod = signWithGo; }
    {name = "Gnupg"; sigMethod = signWithGnupg; }
  ];
  genReportPiece = { grubVersion, pubKeyForm, sigForm }:
    let
      inherit (sigForm) sigMethod;
      grubCfg = pkgs.writeTextFile { name="grub.cfg"; text = grubCfgTextBuilder { inherit (grubVersion) moduleName; }; };
      grubMemdisk = grubMemdiskBuilder rec {
        inherit (pubKeyForm) pubKey;
        signedFile = ./testContent;
        signatureFile = sigMethod { inherit signedFile; };
      };
    in pkgs.runCommand "grubTest-${grubVersion.name}-${pubKeyForm.name}-${sigForm.name}" {inherit grubCfg grubMemdisk;} ''
      mkdir -p ./build
      cp -- "$grubCfg" ./build/grub.cfg || exit
      ${grubVersion.grub}/bin/grub-emu --memdisk="$grubMemdisk" --dir="$PWD/build" | tee ./grub.out >&2
      printf '%-20s %-20s %-20s %-20s %s\n' "${grubVersion.name}" "${pubKeyForm.name}" "${sigForm.name}" "$(tr '\r' '\n' <grub.out | grep -oe '==VERIFY.*==' | tr -d '=')" "${grubVersion.grub}" >"$out"
    '';

  fullReportPieces = pkgs.lib.flatten (builtins.map (grubVersion: builtins.map (pubKeyForm: builtins.map (sigForm: genReportPiece {inherit grubVersion pubKeyForm sigForm;}) sigForms) pubKeyForms) grubVersions);
  fullReport = pkgs.runCommand "grub-report.txt" { inherit fullReportPieces; } ''
    read -r -a fullReportPieces <<<"$fullReportPieces"
    {
      printf '%-20s %-20s %-20s %-20s %s\n' "Version" "Pubkey Format" "Sig Format" "Result" "Grub Build" "===" "===" "===" "===" "==="
      cat "''${fullReportPieces[@]}"
    } >"$out"
  '';
}
