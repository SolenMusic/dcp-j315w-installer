# DCP-J315W macOS Installer

[![Build and verify](https://github.com/SolenMusic/dcp-j315w-installer/actions/workflows/build.yml/badge.svg)](https://github.com/SolenMusic/dcp-j315w-installer/actions/workflows/build.yml)

A graphical macOS installer and native setup/removal app for the **Brother
DCP-J315W**, on Intel and Apple Silicon. Choose **Printing**, **Scanning**, or
**both** in macOS Installer; both are selected by default.

This repository packages pinned releases from
[dcp-j315w-cups](https://github.com/SolenMusic/dcp-j315w-cups) and
[dcp-j315w-scan](https://github.com/SolenMusic/dcp-j315w-scan).
The driver implementations remain in those projects. Downloaded inputs are
verified against fixed SHA256 hashes in `components.json`.

Created with LLM-assisted coding. I hope this helps keep your printer and scanner
useful for a while longer. Source is MIT licensed; each component retains its
own MIT notice. This project is not affiliated with Brother.

## Download v0.1.0

[Download the universal signed and notarized macOS installer](https://github.com/SolenMusic/dcp-j315w-installer/releases/download/v0.1.0/dcp-j315w-installer-0.1.0-macos-universal.pkg).
Checksums and release notes are on the [release page](https://github.com/SolenMusic/dcp-j315w-installer/releases/tag/v0.1.0).

## Included components

| Capability | Printing | Scanning |
| --- | --- | --- |
| Wi-Fi | CUPS printing | Native Image Capture scanning |
| Colour / monochrome | 300/600 dpi | Colour/grayscale and thresholded text, 100/300 dpi |
| Multiple pages | CUPS pages, copies and collation | PDF assembly in Image Capture |
| USB / direct wired connection | Not implemented | Not implemented |
| iOS / AirPrint, Windows | Not implemented | Not implemented |
| Other models | Unverified | Unverified |

The initial bundle contains printing **0.1.1** and scanning **0.1.0**. Installer
versioning is independent of component versioning. macOS 11 is the build target;
physical driver checks were made on macOS 27 with Apple Silicon, not every OS/CPU.

**Linux downloads stay separate** in the printing and scanning repositories.
This installer does not create Linux combined bundles.

## Install and configure

1. Open the signed `.pkg`, proceed to Installation Type and select Printing,
   Scanning or both. If needed use Customize to expose the component checkboxes.
2. Authenticate in macOS Installer. Deselecting a component excludes it from this
   installation; it does not remove a previously installed component.
3. Open **DCP-J315W Setup** from Applications. Use **Find on Network**, or enter
   the printer's IPv4 address. Select the installed components to configure, then
   choose **Configure Selected**.
4. Use **DCP-J315W CUPS Driver** when printing, or **DCP-J315W Open Scanner** in
   Image Capture. Printing may already be discovered during package installation.

The Printing component preserves existing queues for this project's driver and
refuses upgrades while those queues have unfinished jobs. It does not replace
unrelated Brother queues or change the default printer.

Scanning configuration runs in your logged-in account and creates its private
helper/LaunchAgent at login, using the upstream scanner installer. The shared
package files live under Library/Application Support/DCPJ315WInstaller/Scanner.
The package itself does not configure all accounts or start a root scanner daemon.
Each account that wants scanning opens the setup app to configure its own helper.
Bundle relocation is disabled so Installer cannot replace an existing private
scanner helper instead of placing the shared package files.

The setup app uses native macOS fonts and controls. Its administrator dialog
uses macOS authentication; it does not collect or save your password.

## Uninstall on macOS

macOS `.pkg` installation has no automatic uninstall operation. Deleting a printer
in System Settings only removes that queue; moving the setup app to Trash alone
does not remove its installed driver or scanner login helper.

Open **DCP-J315W Setup**, check the components to remove and choose
**Remove Selected**:

- **Printing:** administrator authentication removes all queues using this CUPS
  driver and invokes its upstream uninstaller for its files/public PPD/receipt.
  All matching queues are checked for unfinished jobs before any removal.
  Unrelated queues, including original Brother queues, are kept.
- **Scanning:** removes the shared scanner package files/receipt with administrator
  authentication, then stops/removes this account's private helper and login entry.
  Saved scans and diagnostic logs are kept. Other accounts' configured private
  helpers are independent copies and are preserved; those users remove their own
  scanning configuration while logged in to their account.
- **Setup app:** after both driver components and this user's scanner helper are
  removed, choose **Remove Setup App** to remove the app and its package receipt.

Scans are saved by Image Capture in the location you selected. No uninstall action
searches for or deletes those documents. Removal is scoped to the listed package
paths and this project's queue/filter identifiers.

## Developer build

On macOS with command-line developer tools and Python 3:

```sh
python3 fetch-components.py
./build.sh
./build-installer.sh --unsigned
python3 tests/test_package.py dist/*-unsigned.pkg
```

Python is a build/test dependency only, not an install/configuration dependency.
The setup app is a universal Objective-C/AppKit binary. Public releases require
Developer ID Application and Installer signatures, hardened runtime, notarization
and stapling. Credentials remain in the developer's local keychain; no key or
password is committed or placed in CI.

The read-only package tests inspect real Installer choices, payloads, signatures,
fixed bundle paths and HTML fonts/encoding. `tests/test_install.py` installs,
upgrades and removes the real packages **only on disposable GitHub macOS runners**;
it refuses to run on a personal Mac. Test queues point to localhost port 9 and a
held job is never printed. Physical printer/scanner operation is verified in the
component projects; a combined-install dogfood check is still useful.

The package install/upgrade/removal checks pass on both macOS GitHub runner CPUs.
Native UI layout, invalid-address rejection and Bonjour discovery were checked on
the development macOS 27 Mac. Privileged setup/removal through the GUI and a full
combined-install dogfood scan/print remain user checks.
