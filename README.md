What Is This?
=============

A test suite to determine whether GRUB supports OpenPGP signatures with keyids given in hashed packets, as is the case in detached signatures created by Go crypto/openpgp.

As of 2.02, this didn't work without a patch written by Ignat Korchagin of Cloudflare. Unfortunately, upstream never merged this patch, and major code changes happened between 2.02 and the later 2.04 release, making this patch difficult to port forward.

This is a test framework intended to make it easier to build a successor patch.


How Do I Use It?
================

This currently hardcodes x86_64 as the only supported target architecture; that should be trivial to change, if there's ever a need.

- Install the Nix package manager.

- Run: `nix-build -A fullReport`

- Read the file linked from the symlink named `result` this creates. (`cat result`)


What Does A Report Look Like?
=============================

As of this writing, something like:

```
Version              Pubkey Format        Sig Format           Result               Grub Build
===                  ===                  ===                  ===                  ===
GRUB_2.02_Unpatched  Go                   Go                   VERIFY FAILED        /nix/store/r9bwr77fa476zq0k0mxzqz9qbvgawv6i-grub-2.02
GRUB_2.02_Unpatched  Go                   Gnupg                VERIFY FAILED        /nix/store/r9bwr77fa476zq0k0mxzqz9qbvgawv6i-grub-2.02
GRUB_2.02_Unpatched  Gnupg                Go                   VERIFY FAILED        /nix/store/r9bwr77fa476zq0k0mxzqz9qbvgawv6i-grub-2.02
GRUB_2.02_Unpatched  Gnupg                Gnupg                VERIFY SUCCEEDED     /nix/store/r9bwr77fa476zq0k0mxzqz9qbvgawv6i-grub-2.02
GRUB_2.02_Patched    Go                   Go                   VERIFY FAILED        /nix/store/szsk26vvxbpjdlzsldn0vkpx0r74hrcy-grub-2.02
GRUB_2.02_Patched    Go                   Gnupg                VERIFY FAILED        /nix/store/szsk26vvxbpjdlzsldn0vkpx0r74hrcy-grub-2.02
GRUB_2.02_Patched    Gnupg                Go                   VERIFY SUCCEEDED     /nix/store/szsk26vvxbpjdlzsldn0vkpx0r74hrcy-grub-2.02
GRUB_2.02_Patched    Gnupg                Gnupg                VERIFY SUCCEEDED     /nix/store/szsk26vvxbpjdlzsldn0vkpx0r74hrcy-grub-2.02
GRUB_2.04_Unpatched  Go                   Go                   VERIFY FAILED        /nix/store/49fgagxwcvv6pid6axs2g0953nynknpn-grub-2.04
GRUB_2.04_Unpatched  Go                   Gnupg                VERIFY FAILED        /nix/store/49fgagxwcvv6pid6axs2g0953nynknpn-grub-2.04
GRUB_2.04_Unpatched  Gnupg                Go                   VERIFY FAILED        /nix/store/49fgagxwcvv6pid6axs2g0953nynknpn-grub-2.04
GRUB_2.04_Unpatched  Gnupg                Gnupg                VERIFY SUCCEEDED     /nix/store/49fgagxwcvv6pid6axs2g0953nynknpn-grub-2.04
GRUB_master          Go                   Go                   VERIFY FAILED        /nix/store/lagkfcw1yy3v0843w18qf2mc5yywc57a-grub-master
GRUB_master          Go                   Gnupg                VERIFY FAILED        /nix/store/lagkfcw1yy3v0843w18qf2mc5yywc57a-grub-master
GRUB_master          Gnupg                Go                   VERIFY FAILED        /nix/store/lagkfcw1yy3v0843w18qf2mc5yywc57a-grub-master
GRUB_master          Gnupg                Gnupg                VERIFY SUCCEEDED     /nix/store/lagkfcw1yy3v0843w18qf2mc5yywc57a-grub-master
```

...telling us that:

- The patched version of 2.02, unlike all others, can verify signatures created by go/crypt/openpgp
- All known versions of GnuPG, including the patched one, can't read public-key files exported by go/crypt/openpgp.

...and giving us a directory name where we can find the (debug-symbol-enabled) GRUB binaries that were used to generate each test result.


What Future Enhancements Are Pending?
=====================================

- [X] Signatures created by go's openpgp library need to be included in the sample results given above.
- [X] The table of results should include the derivation names, so `nix log` can be used to include the logs for the individual test runs, or `nix show-derivation` can be used to see the components and build steps that went into that test run.
- [ ] A patched version of grub 2.04 is expected to be added, as a patch is developed.


How Is This Content Licensed?
=============================

GNU GRUB is GPLv3+. Derived works from it fall under that same license.

All other content is MIT-licensed. (This includes content from the nixpkgs repository, for which copyright is held by various contributors to the NixOS project).

Repository content not taken from any other source is owned by myself, Charles Duffy <charles@dyfis.net>, in my personal capacity (took time off work to do this, using only personally-owned hardware, and making no reference to or use of employer-owned intellectual property). This content is explicitly *not* work-for-hire or otherwise property of my employer.
