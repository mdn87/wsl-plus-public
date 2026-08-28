# Home network recovery

This runbook is Home-only. It does not apply to a distro on the `restricted` policy, where Windows interop and boundary changes require separate policy review.

## Trigger condition

Use this path when Windows has working network access but a Home WSL distro loses DNS or general connectivity, often after connecting a VPN.

## First-line recovery

1. Record whether Windows, WSL, or both are affected.
2. Test raw IP connectivity separately from DNS resolution.
3. Exit active WSL sessions and run:

   ```powershell
   wsl --shutdown
   ```

4. Reopen the distro and retest.
5. Review Windows `%UserProfile%\.wslconfig` before changing Linux resolver files.
6. Prefer current WSL networking options such as mirrored networking, DNS tunneling, and Windows proxy discovery when they fit the host.

WSL Plus does not edit `.wslconfig`, `/etc/wsl.conf`, `/etc/resolv.conf`, VPN routes, or Windows firewall rules automatically.

## VPNKit fallback

Treat `wsl-vpnkit` as an exceptional Home fallback only when:

- the failure is tied to a Windows VPN,
- normal WSL restart and networking options did not solve it,
- Windows executable interop is available,
- the operator accepts the additional networking component.

Do not install or start it automatically. Do not use it under the `restricted` policy.

Upstream project: <https://github.com/sakai135/wsl-vpnkit>

## Evidence to retain

Before and after a recovery attempt, retain:

```bash
ip address
ip route
cat /etc/resolv.conf
getent hosts github.com
```

From Windows, retain the relevant output from:

```powershell
wsl --status
wsl --version
Get-NetIPConfiguration
```

Do not copy VPN credentials, private DNS names, or internal endpoint addresses into public issue reports.
