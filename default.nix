{system ? builtins.currentSystem}: 
let
  pkgs = import <nixos> {inherit system;};
  inherit (pkgs) stdenv;
  grubDevBuild = grubPkg: pkgs.enableDebugging (grubPkg.overrideAttrs (a: a // {configureFlags = ["--with-platform=emu" "--target=x86_64"];} ));
in rec {
  inherit pkgs;
  grub_202 = grubDevBuild (pkgs.callPackage ./pkgs/grub_2.02/2.0x.nix { zfsSupport = false; });
  grub_202_patched = grubDevBuild ((pkgs.callPackage ./pkgs/grub_2.02/2.0x.nix { zfsSupport = false; }).overrideAttrs (a: a // {patches = [./pkgs/grub_2.02/openpgp-hashed-keyid-subpacket.patch] ++ a.patches;}));
  grub_204 = grubDevBuild (pkgs.callPackage ./pkgs/grub_2.04/2.0x.nix { zfsSupport = false; });

  grubRamdisk = pkgs.runCommand "grub-test.tar" {content = ./grub-ramdisk.d;} with pkgs; ''
    [ -d "$out" ] && { rmdir "$out" || exit; }
    ${pkgs.tar} --mtime=@0 -f "$out" -C "$content" -c .
  '';
}
