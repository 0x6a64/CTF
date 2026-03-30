# pkgs/vuln-binaries/bof-server/default.nix
#
# Intentionally vulnerable network service for the pwn-bof challenge.
#
# The binary reads from stdin into a fixed 64-byte stack buffer with no
# bounds checking.  A 32-bit x86 build is used so that classic BOF techniques
# (EIP overwrite, ret2win) work without requiring ROP chains.
#
# The win() function reads /etc/flag and prints it — the participant must
# overflow the buffer and redirect execution there.
{ stdenv, writeText }:

let
  src = writeText "bof-server.c" ''
    /*
     * Intentionally vulnerable network service — NixCTF pwn-bof challenge.
     *
     * This program is deliberately insecure.  Do NOT deploy outside of an
     * isolated CTF VM environment.
     *
     * Stack layout (approximate, x86-32):
     *   [buf 64 bytes][saved ebp 4 bytes][saved eip 4 bytes] ...
     * Overflow buf by >= 68 bytes to control eip.
     */
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>

    /* win() is the target — overflowing the buffer and redirecting here
       prints the flag. */
    void win(void) {
        FILE *f = fopen("/etc/flag", "r");
        if (!f) {
            puts("flag file not found — is /etc/flag present?");
            return;
        }
        char flag[128];
        if (fgets(flag, sizeof(flag), f)) {
            printf("Congratulations! Flag: %s\n", flag);
        }
        fclose(f);
    }

    void vuln(void) {
        char buf[64];
        printf("win() is at: %p\n", (void *)win);
        printf("Enter your name: ");
        fflush(stdout);
        /*
         * Intentionally vulnerable: read() with no length check, equivalent
         * to the classic gets() overflow.  Using read() avoids linker errors
         * on modern glibc where gets() has been removed (C11 / glibc >= 2.28).
         */
        read(0, buf, 256);
        printf("Hello, %s!\n", buf);
    }

    int main(void) {
        /* Disable stdout buffering so output appears immediately over socat. */
        setvbuf(stdout, NULL, _IONBF, 0);
        setvbuf(stderr, NULL, _IONBF, 0);
        vuln();
        return 0;
    }
  '';
in
stdenv.mkDerivation {
  pname   = "bof-server";
  version = "1.0.0";

  src = src;
  unpackPhase = "cp $src bof-server.c";

  buildPhase = ''
    # -m32            : 32-bit binary for classic BOF techniques
    # -fno-stack-protector : disable stack canary
    # -no-pie         : disable ASLR / position-independent executable
    # -z execstack    : allow shellcode on the stack
    # -O0             : no optimisation (preserves stack layout)
    $CC -m32 -fno-stack-protector -no-pie -z execstack -O0 \
        -o bof-server bof-server.c \
        -Wno-implicit-function-declaration \
        || \
    $CC -fno-stack-protector -no-pie -z execstack -O0 \
        -o bof-server bof-server.c \
        -Wno-implicit-function-declaration
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp bof-server $out/bin/bof-server
  '';

  meta = {
    description = "Intentionally vulnerable buffer-overflow server for the NixCTF pwn-bof challenge";
    license     = { spdxId = "GPL-2.0-only"; fullName = "GNU General Public License v2.0 only"; };
  };
}
