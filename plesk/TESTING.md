# Testing the Plesk extension

Everything the agent returns is **server-wide**: every account's sites, bans, events and findings, and
the server's allow list (docs/panel-json.md, "Who may see it"). The agent has no notion of resellers or
customers, so v1 is for the Plesk administrator only: every controller is admin-only, the buttons and the
Home block exist only in administrator places, and the root wrapper can be run only by Plesk through
`callSbin`. The Security checklist below checks that a customer gets nothing.

Two ways: a disposable Docker container (quick, what development used), and a real VM (needed before a
release). Never install the mock agent on a production or customer server.

## 1. Build

```sh
cd plesk
./build.sh            # → dist/infrafence-plesk-1.0.0-1.zip
```

## 2. Quick test in Docker (plesk/plesk image)

Works on Linux and on macOS with OrbStack or Docker Desktop; on Apple Silicon the image runs under amd64
emulation (slow to start, about 2 minutes, but usable). The trial key installs itself. Limits of the trial
in a container: one domain, English only, and a EULA dialog that cannot be accepted (close it or work
around it); everything the extension does can still be tested.

```sh
docker run -d --platform linux/amd64 --name plesk-test \
  -p 8880:8880 -p 8443:8443 \
  --tmpfs /tmp --tmpfs /run --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw --cgroupns=host \
  plesk/plesk:latest

docker cp dist/infrafence-plesk-1.0.0-1.zip plesk-test:/root/
docker exec plesk-test plesk bin extension -i /root/infrafence-plesk-1.0.0-1.zip
dev/install-mock.sh plesk-test
docker exec plesk-test plesk bin subscription --create blog-example.org -owner admin \
  -service-plan "Default Domain" -ip "$(docker exec plesk-test plesk bin ipmanage -l | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)" \
  -login blogex -passwd 'Choose-A-Password-1'
docker exec plesk-test plesk login       # open the printed URL, with port 8880 (http) or 8443 (https)
```

Then follow the checklist in section 4.

## 3. Real VM

Use a fresh, disposable VM: Ubuntu 22.04/24.04, Debian 12, AlmaLinux 8/9 or Rocky Linux 8/9, 2 vCPU and 4 GB
of RAM or more, with a public or private IP you can reach.

1. Install Plesk Obsidian with the one-click installer, as root:

   ```sh
   sh <(curl https://autoinstall.plesk.com/one-click-installer || wget -O - https://autoinstall.plesk.com/one-click-installer)
   ```

   Open `https://<vm>:8443`, finish the initial setup, and apply a trial or test licence. For the
   language checks use a licence that allows more than one language (the free trial allows English only).
2. Optional, to make the Coexistence screen realistic: install the Fail2Ban, Firewall and ModSecurity
   components (Tools & Settings › Updates › Add/Remove Components), and Imunify360 from the catalog on a
   separate VM.
3. Create two or three subscriptions with hosting, so that the Domains screen has rows.
4. Copy the zip to the VM and install it: `plesk bin extension -i infrafence-plesk-1.0.0-1.zip`.
5. Agent:
   - **with the real agent**: install it with the command shown on the extension's "not installed" screen
     and enroll the VM in a test organisation in the dashboard;
   - **with the mock**: copy `dev/` to the VM and run `sudo sh dev/install-mock.sh --here`.
6. Follow the checklist below in Chrome or Firefox, logged in as `admin`.
7. When done, remove the mock (`rm -rf /usr/local/sbin/infrafence-agent /usr/local/share/infrafence-mock
   /var/lib/infrafence-mock /etc/infrafence-mock`) or destroy the VM.

## 4. Checklist

The mock answers with the agent's reference outputs (`dev/fixtures/`, a cPanel server: `/home/...` document
roots). Switches, as root:

- `echo running|stopped|disconnected|monitor|suspended > /etc/infrafence-mock/mode`
- `echo "192.0.2.10" > /etc/infrafence-mock/own` makes those addresses the server's own (allow answers
  `already` with `own_address: true`).
- `echo 30 > /etc/infrafence-mock/delay` makes it slower than the wrapper's 25 s timeout; `echo 0` to undo.
- State (unbans, allow-list changes, the running scan) is in `/var/lib/infrafence-mock/state.json`; write
  `{"unbanned":[],"allowed":[],"disallowed":[],"scan_started":null,"events":[]}` into it to start again.
- To try "Scan now" for real, add a Plesk site to the **installed** copy,
  `/usr/local/share/infrafence-mock/fixtures/sites.json`, for example
  `{"account":"blogex","document_root":"/var/www/vhosts/blog-example.org/httpdocs","domain":"blog-example.org","kind":"site","scan_covered":true,"scannable":true}`,
  and one with `"scannable":false` to see "Cannot be scanned". Leave `dev/fixtures/` as it is: it must stay
  identical to the agent's reference.

### Install and integration

- [ ] `plesk bin extension -i` succeeds; `ls -l /usr/local/psa/admin/sbin/modules/infrafence/` shows
      `infrafence-panel` owned by root, mode 755.
- [ ] Left navigation (Server Management) has **InfraFence**; Home › Custom Buttons has the InfraFence button.
- [ ] Home page shows the **InfraFence** block ("This server is protected", active bans, "Open InfraFence").
      If the Home page was customized before, add it from Customize › Security.
- [ ] `grep -i infrafence /var/log/plesk/panel.log` shows no errors after browsing every screen.

### Screens (mode `running`)

- [ ] Overview: Protected, version 1.0.23, last heartbeat and last sync "just now", Mode, plan Pro, AutoMode
      "Not reported by the dashboard", Server ID 42, and "Open in InfraFence" opens
      `https://app.infrafence.com/servers/42` in a new tab. The three counts link to their tabs.
- [ ] Bans: four rows, two of them with no reason and no creation time ("–"), one permanent.
- [ ] Allow list: one entry added from the panel (with Remove) and two from the dashboard (one a range,
      "In the dashboard", no Remove).
- [ ] Findings (filter All/Malware/File integrity, first and last seen), Events (24 h / 7 d / 30 d, "Reported
      by"), Coexistence (five tools, coexist mode, firewall tools named), Domains (four sites, "Scheduled scan").
- [ ] Browser back/forward moves between tabs; reloading keeps the tab (URL `#bans`, …).

### Actions (every one asks for confirmation first)

- [ ] Unban `203.0.113.7` (this server's own detection): the dialog says "lifted on this server only, until
      <date> at the latest" (its expiry); the toast repeats the agent's `lifted_until`; the row disappears;
      Events shows "Address unbanned from the panel".
- [ ] Unban `198.51.100.23` (AutoMode) and `192.0.2.50` (network): dialog and toast also say that the
      organization keeps the ban on its other servers.
- [ ] Unban `198.51.100.9` (dashboard, permanent) with "Also add it to the allow list" and a note: the date is
      30 days from now, the dialog says the ban stays in the dashboard; the address is in Allow list with the
      note, added by `admin`.
- [ ] Add one of the addresses in `/etc/infrafence-mock/own` → warning that it is this server's own address.
- [ ] Add `10.0.0.0/8` → the confirm button stays disabled; `0.0.0.0` and `127.0.0.1` → inline errors;
      `203.0.113.20` → "already allowed"; `203.0.113.55` → added.
- [ ] Remove `198.51.100.4` → removed. Dashboard entries have no Remove.
- [ ] Domains › Scan now on a site under `/var/www/vhosts` (see above) → "scan has started"; at once again →
      "already running"; on a `/home/...` fixture site → "not the document root of any site" (refused by the
      wrapper: Plesk document roots are under the vhosts directory); a `scannable: false` site has no button but the short reason "Not owned by the site's account" (details on
      hover).
- [ ] Tools & Settings › Action Log shows `ext_infrafence_*` entries for the actions above.

### Agent states

- [ ] `stopped`: red banner above the tabs, Overview "Not protected" with "–" for what only the running agent
      knows, lists show no stale empty state, Coexistence and Domains still answer, Scan now disabled, Home
      block "The InfraFence agent is not running".
- [ ] `disconnected`: yellow banner, Overview "Protected locally, not connected".
- [ ] `monitor`: yellow "Monitor mode" banner (once, also on Bans), Overview "Monitor mode".
- [ ] `suspended`: red banner about the plan's server limit, Overview "Not protected".
- [ ] `delay` 30: screens show "did not answer in time" after 25 s; Plesk stays responsive.
- [ ] Untrusted binary: `chmod 777 /usr/local/share/infrafence-mock/mock-agent` → "not owned by root or can be
      modified by other users"; restore with `chmod 755`.
- [ ] Not installed: `chmod 644 /usr/local/share/infrafence-mock/mock-agent` (or remove the agent) → the
      screen that sends you to Servers > Add server, with a link to https://infrafence.com/add-server;
      `chmod 755` again and press "Check again".

### Security

- [ ] As root: `sh dev/test-wrapper.sh` → "all checks passed".
- [ ] On the build machine: `python3 dev/check-mock.py` → "all checks passed" (build.sh runs it too).
- [ ] Symlink escape: `ln -s /etc /var/www/vhosts/<domain>/evil` then
      `infrafence-panel scan /var/www/vhosts/<domain>/evil --actor admin` → `not_a_document_root`; remove the link.
- [ ] Log in as a customer (and as a reseller if the licence allows one): `/modules/infrafence/index.php/index/index`
      and `/modules/infrafence/index.php/api/status` return no agent data, and the extension is not in their
      navigation or on their Home page. The data is server-wide, so this must hold for every non-admin user.
- [ ] In the browser console, a `fetch` POST to `…/api/unban` without the `X-Forgery-Protection-Token`
      header is rejected by Plesk ("Forgery protection token check failed" in panel.log).
- [ ] GET `…/api/unban?ip=…` → 405.

### Look

- [ ] Default (Contrast) and dark theme (moon icon in the header): every screen and dialog readable.
- [ ] Each language (Profile & Preferences › Interface language): tabs, dialogs, toasts and relative times
      are translated; no `[[key]]` placeholders anywhere, including the left navigation.
- [ ] Window at 1280 px and at 1920 px wide; Overview shows two columns from medium widths.

### Uninstall

- [ ] `plesk bin extension -u infrafence` → the sbin directory, the buttons and the Home block are gone;
      the agent and its bans are untouched.
