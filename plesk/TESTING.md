# Testing the Plesk extension

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

Mock agent switches (as root): `echo running|stopped|disconnected > /etc/infrafence-mock/mode`,
`echo 30 > /etc/infrafence-mock/delay` to make it slower than the wrapper's 25 s timeout
(`rm /etc/infrafence-mock/delay` afterwards). Mock state lives in `/var/lib/infrafence-mock/state.json`;
delete it to start again.

### Install and integration

- [ ] `plesk bin extension -i` succeeds; `ls -l /usr/local/psa/admin/sbin/modules/infrafence/` shows
      `infrafence-panel` owned by root, mode 755.
- [ ] Left navigation (Server Management) has **InfraFence**; Home › Custom Buttons has the InfraFence button.
- [ ] Home page shows the **InfraFence** block ("This server is protected", active bans, "Open InfraFence").
      If the Home page was customized before, add it from Customize › Security.
- [ ] `grep -i infrafence /var/log/plesk/panel.log` shows no errors after browsing every screen.

### Screens (mode `running`)

- [ ] Overview: Protected, version, last heartbeat "just now", plan, AutoMode with its explanation, and
      "Open in InfraFence" opens `https://…/servers/<id>` in a new tab. The three counts link to their tabs.
- [ ] Bans: six rows; the search filters by address and reason; IPv6 is shown in full.
- [ ] Allow list, Findings (filter All/Malware/File integrity), Events (24 h / 7 d / 30 d),
      Coexistence (detected tools first, not found greyed out), Domains (Plesk domains plus the agent's).
- [ ] Browser back/forward moves between tabs; reloading keeps the tab (URL `#bans`, …).

### Actions (every one asks for confirmation first)

- [ ] Unban an address → toast, the row disappears, Events shows "Address unbanned" by `plesk:admin`.
- [ ] Unban with "Also add it to the allow list" and a note → it appears in Allow list with the note.
- [ ] Add `10.0.0.0/8` → the confirm button stays disabled; add `127.0.0.1` → inline error;
      add `203.0.113.55` → added. Adding an address already covered by an entry → inline error naming it.
- [ ] Remove an allow-list entry → removed.
- [ ] Domains › Scan now on a Plesk domain → "Queued"; the button is disabled while queued.
- [ ] Tools & Settings › Action Log shows `ext_infrafence_*` entries for the actions above.

### Agent states

- [ ] `stopped`: red banner above the tabs, Overview "Not protected", lists show no stale empty state,
      Scan now disabled, Home block "The InfraFence agent is not running".
- [ ] `disconnected`: yellow banner, Overview "Protected locally, not connected".
- [ ] `delay` 30: screens show "did not answer in time" after 25 s; Plesk stays responsive.
- [ ] Untrusted binary: `chmod 777 /usr/local/share/infrafence-mock/mock-agent` → "not owned by root or can be
      modified by other users"; restore with `chmod 755`.
- [ ] Not installed: `rm /usr/local/sbin/infrafence-agent` → install screen with the command and Copy;
      put the link back and press "Check again".

### Security

- [ ] As root: `sh dev/test-wrapper.sh` → "all checks passed".
- [ ] Symlink escape: `ln -s /etc /var/www/vhosts/<domain>/evil` then
      `infrafence-panel scan /var/www/vhosts/<domain>/evil --actor x` → `invalid_path`; remove the link.
- [ ] Log in as a customer: `/modules/infrafence/index.php/api/status` returns no agent data and the
      extension is not in the customer's navigation.
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
