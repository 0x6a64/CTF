# pkgs/vuln-binaries/suid-shell/default.nix
#
# Intentionally vulnerable SUID binary for the suid-privesc challenge.
#
# The binary calls setuid(0)/setgid(0) and then executes a shell, dropping
# any participant who can run it into a root shell.  When deployed via the
# suid-privesc challenge module this binary is installed with the SUID bit
# set (via security.wrappers), so any user can invoke it to become root.
{ stdenv, writeText }:

let
  src = writeText "suid-shell.c" ''
    /*
     * Intentionally vulnerable SUID binary — NixCTF suid-privesc challenge.
     *
     * This program is deliberately insecure.  Do NOT deploy outside of an
     * isolated CTF VM environment.
     */
    #include <stdio.h>
    #include <stdlib.h>
    #include <unistd.h>

    int main(void) {
        /* Drop to root via the SUID bit. */
        if (setuid(0) != 0 || setgid(0) != 0) {
            fprintf(stderr, "setuid/setgid failed — are you running as root or is the SUID bit set?\n");
            return 1;
        }
        printf("Elevated to UID=%d GID=%d\n", getuid(), getgid());
        printf("Spawning root shell...\n");
        execl("/bin/sh", "sh", NULL);
        perror("execl");
        return 1;
    }
  '';
in
stdenv.mkDerivation {
  pname   = "suid-shell";
  version = "1.0.0";

  # Feed the C source directly — no tarball needed.
  src = src;
  unpackPhase = "cp $src suid-shell.c";

  buildPhase = ''
    $CC -o suid-shell suid-shell.c
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp suid-shell $out/bin/suid-shell
  '';

  meta = {
    description = "Intentionally vulnerable SUID binary for the NixCTF suid-privesc challenge";
    license     = { spdxId = "GPL-2.0-only"; fullName = "GNU General Public License v2.0 only"; };
  };
}
