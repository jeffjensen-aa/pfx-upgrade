# PFX upgrade

Convert a legacy PFX to an OpenSSL 3-compatible PFX without modifying the source.
The output uses OpenSSL 3's default export algorithms (AES-256-CBC and SHA-256).

## Windows

Run from PowerShell 7 on x64 Windows:

```powershell
.\setup-openssl.ps1
.\convert-pfx.ps1 .\old.pfx .\new.pfx
# Optional PEM intermediate-certificate bundle:
.\convert-pfx.ps1 .\old.pfx .\new-with-chain.pfx .\chain.pem
```

Setup downloads the Shining Light OpenSSL 3.5.9 LTS Light installer, verifies its
SHA-256, and launches it interactively with a destination under
`$HOME\.local\pfx-upgrade`. Keep that destination when following the installer
prompts. The installer may request elevation; select its option to copy DLLs to
the OpenSSL binaries directory rather than the Windows system directory.

## Linux / macOS Bash

```bash
bash setup-openssl.sh
bash convert-pfx.sh old.pfx new.pfx
# Optional PEM intermediate-certificate bundle:
bash convert-pfx.sh old.pfx new-with-chain.pfx chain.pem
```

Setup requires Curl, Tar, Make, Perl, a C compiler and development headers, and
`sha256sum` or `shasum`. It verifies the official OpenSSL 3.5.9 source SHA-256,
builds with legacy support, and installs under
`$HOME/.local/pfx-upgrade` without replacing system OpenSSL.

Both converters automatically prefer the setup script's local OpenSSL. Otherwise
they use OpenSSL on `PATH`, which must be version 3.x.

## Passwords and certificate chains

OpenSSL prompts interactively for the source PFX password, a temporary PEM-key
passphrase (including confirmation), that key passphrase again, and the new PFX
password (including confirmation). No passwords are stored in the scripts or
passed as command-line arguments. Temporary private keys remain encrypted.

The destination must not already exist. Temporary conversion files are removed
on normal completion or handled failure. A forced process termination or power
loss can leave temporary files behind.

If intermediates are needed, explicitly supply a PEM chain bundle; certificates
embedded in the source PFX's chain are not automatically copied. The scripts
repackage the certificate and key; they do not renew certificates or upgrade
their key or signature algorithms.

Use `-Help` (PowerShell) or `--help` (Bash) for usage.
