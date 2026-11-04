# Lab operations

Read when the guest, Appium setup, WDA, signing certificates or Maestro on Android misbehave, or when building Android on this host.

## Guest reachability

`vmrun list` and `vmrun getGuestIPAddress` can fail while the guest is healthy (degraded VMX channel). `MobileLabGuest.psm1` proposes an address from the cache, `C:/ProgramData/VMware/vmnetdhcp.leases`, `ssh_config`, then `vmrun`, and accepts only one that SSH reaches. `Start-MobileLab.ps1` calls `vmrun start` only when SSH, `vmrun list` and the `vmware-vmx` process all say the guest is down. By hand:

```powershell
Import-Module .\scripts\MobileLabGuest.psm1
Resolve-MobileLabGuestAddress -SkipVmrun
Get-MobileLabLeaseAddresses
```

## VMware host services

`registry/mobile-development.json` (`vmware-workstation.discovery.hostServices`) lists the services. `start ios` checks them only when the guest is down and, if one is stopped, names it with the elevated commands before calling vmrun. `check runtime ios` and `Test-MobileLab.ps1` only report them. `-RepairVmwareServices` touches only registered, installed, not-running services, sets Manual to Automatic, starts them, refuses Disabled services, and fails without elevation.

## Guest setup and WDA

- `setup-appium-guest.sh` fails closed: it exits non-zero naming the step when an install is off the registry pin, the doctor times out, fails or runs nothing, or the WDA build fails. It rebuilds WDA only when the xcuitest version, WebDriverAgent version or Xcode build changed (`~/mobile-lab/state/wda-build.key`); `--force-wda` overrides.
- Retire a stale runner with `cleanup-wda-guest.sh <udid>`. Never `pkill` or `simctl shutdown all`; other sessions own those processes.
- `usePrebuiltWDA` loops on `connect ECONNREFUSED 127.0.0.1:8100` unless `xcrun simctl listapps booted | grep -i WebDriverAgent` shows WDA installed.
- Install npm packages in the guest as the user, never with `sudo` (nvm-owned node).
- Appium binds `0.0.0.0` on the single private VMnet8 NIC, because the DHCP address changes. It enables only `*:session_discovery`; deep validation depends on it.
- Ask `xcodebuild -version`; never test for `/Applications/Xcode.app` (xcodes installs `Xcode-<version>.app`).
- `applesimutils` stays uninstalled: its tap is untrusted, a supply-chain decision for the owner (`brew trust wix/brew && brew install applesimutils`).

## macOS VM settings

Keep `cpuid.coresPerSocket = "1"` with `numvcpus = "4"`; any other value stops the guest booting with no error. A guest whose `vmware-vmx` working set stays near 15 MB is not executing. Keep `vhv.enable = "FALSE"` (the starter repairs it). Change `numvcpus` alone when tuning. The guest is x86_64, so Xcode stops at 26.x (`registry/mobile-development.json` `expectations.xcode`).

## Android build on Windows

Every local `gradlew` run fails with `Unable to establish loopback connection` unless TEMP is outside `%LOCALAPPDATA%\Temp` (AF_UNIX sockets are rejected there):

```powershell
$env:TEMP='C:\Temp'; $env:TMP='C:\Temp'
cd <repo>\android; .\gradlew.bat :app:assembleRelease -PreactNativeArchitectures=x86_64
```

Do not use `JDK_JAVA_OPTIONS`; its stderr banner breaks the NDK CMake step. Android Studio is not installed; use `sdkmanager` and `avdmanager`. The AVD name and API come from the registry.

## Signed iOS builds in the guest

"Distribution certificate ... hasn't been imported successfully" usually means the WWDR intermediates are missing, so `security find-identity -v` filters the identity out. Diagnose, then import into the login keychain only (no system trust changes):

```bash
security find-certificate -a -c "Apple Worldwide Developer Relations" -p | openssl x509 -noout -subject -dates
for g in G2 G3 G4 G5 G6; do
  curl -fsSL -o "AppleWWDRCA$g.cer" "https://www.apple.com/certificateauthority/AppleWWDRCA$g.cer"
  security import "AppleWWDRCA$g.cer" -k ~/Library/Keychains/login.keychain-db
done
```

Zero valid identities does not distinguish "no certificate" from "unvalidatable certificate".

## Maestro on Android

Run it from the guest over an SSH reverse tunnel, so one Maestro install covers both platforms and adb keeps its loopback bind:

```bash
ssh macvm 'adb kill-server'
ssh -f -N -R 5037:127.0.0.1:5037 macvm
maestro --device emulator-5554 test flow.yaml
```

Always pass `--device`; bare `maestro test` silently picks the guest's iOS simulator. `ADB_SERVER_SOCKET` configures adb but not Maestro. WSL cannot reach the Windows adb in its default configuration.

## Fixed choices

- One device-control MCP server (`appium-mcp`, pin in `registry/mcps.json`); do not add Maestro MCP.
- Android and iOS run concurrently; no reboot or alternation.
- Node versions are not standardized; both runtimes already satisfy the packages.
- `build-expo-simulator.sh` defaults to Release (standalone binary); `--dev` is for development.
