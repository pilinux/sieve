# Sieve

[![macOS 26.6 or later][badge-macos]](#what-you-need)
[![Apple silicon][badge-arch]](#what-you-need)
[![Swift 6][badge-swift]](#project-layout)
[![Licence: GPL-3.0-only][badge-licence]](LICENSE)

Sieve is a firewall for the connections your Mac makes. It shows every
app that goes online and every host it contacts. You allow or block
each app, or single domains of an app. One switch blocks about 78,000
ad, tracker, and malware domains. Everything stays on your Mac.

![The Apps screen of Sieve](docs/images/apps.jpg)

| Part | What you will find |
| --- | --- |
| [1. Get started](#1-get-started) | Features, needs, install, setup |
| [2. Use Sieve](#2-use-sieve) | Each screen, with pictures and recipes |
| [3. Under the hood](#3-under-the-hood) | Design, limits, developer answers |

## 1. Get started

### What Sieve does

| Feature | What it does |
| --- | --- |
| Per-app rules | Allow or block every outgoing connection of an app. |
| Per-domain rules | Keep an app online, but block single domains. |
| Ask mode | Pause an unknown app's first connection and ask you. |
| Quiet mode | Allow and record unknown apps. Decide later, in one pass. |
| Tracker Shield | Block Steven Black's list of ad and tracker domains. |
| Domain lists | Add your own allow and block lists by URL or file. |
| App X-Ray | Every host an app contacts, its trackers, and a grade. |
| Traffic monitor | The live rate of each app, in the window and menu bar. |
| Rule insights | Hits and last hit per rule, and flags on dead rules. |
| Data limits | Cap an app's data per day or per month. |
| Profiles | Rule sets that switch by network or by time. |

Sieve has no account, no server, no analytics, and no third-party code.
It collects no data. See the [privacy policy](PRIVACY.md).

### What you need

- macOS 26.6 or later.
- A Mac with Apple silicon. Builds include Intel, but only Apple
  silicon is tested.
- An administrator password, once, to allow the filter.

### Install

- **Mac App Store:** [Sieve on the Mac App Store][appstore].
- **Homebrew:**

  ```sh
  brew install --cask pilinux/tap/sieve
  ```

macOS runs the filter only when Sieve is in `/Applications`. Both ways
put it there.

### Set up

![The setup steps](docs/images/setup.jpg)

1. Open Sieve. The window shows **Off** and a **Turn on** button.
2. Click **Turn on**. macOS asks to allow the system extension.
3. Open **System Settings > General > Login Items & Extensions >
   Network Extensions** and switch Sieve on. The window links to that
   page.
4. If macOS asks whether Sieve may filter network content, click
   **Allow**.

The window then shows the Apps screen. A new install starts in **Quiet**
mode with **Tracker Shield** on: nothing breaks, and Sieve starts to
learn what your apps do.

> [!TIP]
> Turn on **Launch at login** at the bottom of the sidebar. In ask mode,
> the app will require your attention for the first connection of an
> unknown app.

### Remove Sieve

1. Drag Sieve from `/Applications` to the Trash.
2. macOS offers to remove the filter. Accept.
3. Sieve's data stays in a folder only an administrator can read. To
   delete it too:

   ```sh
   sudo rm -rf /var/root/Library/Containers/me.pilinux.Sieve.SieveExtension
   ```

## 2. Use Sieve

The pictures come from Sieve's design prototypes, with sample apps and
hosts. The app matches them.

### Pick a mode

The toolbar switches between three modes.

| Mode | An app with no rule | Use it when |
| --- | --- | --- |
| Off | Everything is allowed. | You want to pause the firewall. |
| Ask | Sieve pauses it and asks you. | You want to decide each app. |
| Quiet | Sieve allows and records it. | You decide later, in one pass. |

Rules and lists apply in Ask and Quiet mode alike. Only Off skips them.

> [!IMPORTANT]
> In Ask mode, Sieve blocks apps with no rule while the Sieve app is not
> running. Otherwise any program could quit Sieve to get through.

### Apps

![The Apps screen](docs/images/apps.jpg)

- Every app that connected, with its rate, its data, and a privacy
  grade from A to F.
- **Undecided** holds apps with no rule yet. Click ✕ to block or ✓ to
  allow.
- A switch on each app allows or blocks it.
- The overview shows the live rate, 31 days of data, blocked
  connections, and trackers seen.

The grade counts the tracker hosts an app reached that your rules and
lists still let through:

| Grade | A | B | C | D | F |
| --- | --- | --- | --- | --- | --- |
| Open trackers | 0 | 1 to 2 | 3 to 5 | 6 to 10 | 11 or more |

An app that gave no host names shows `–`: its trackers are unknown.

### The Ask prompt

![Four Ask prompts](docs/images/prompt.jpg)

In Ask mode, the first connection of an app with no rule waits for you.

- The prompt shows the app's path and its verified signer. A signer that
  Sieve cannot verify shows in red.
- It shows the host, or the IP address when the app gave no host name.

**This host only** sets how wide your answer is:

| This host only | Allow or Block makes | After that |
| --- | --- | --- |
| Off | A rule for the whole app | The app never asks again |
| On | A rule for this host | The app may ask for other hosts |

For example, an app wants `telemetry.example.com`. Block with **This
host only** on drops that host and keeps the app working. Block with it
off cuts the app off.

### App X-Ray

![App X-Ray](docs/images/xray.jpg)

Select an app to see every host it contacted.

- Hosts on a block list carry a tracker mark.
- Each host has its own Allow and Block.
- Set a **data limit** per day or per month. Over the limit, the app's
  new connections fail until the period ends.
- **Clear history** (the round clock button) deletes the app's hosts
  and byte counts. Its rules and limit stay.

### Lists

![The Lists screen](docs/images/lists.jpg)

**Tracker Shield** is one switch. It holds [Steven Black's unified
hosts][hosts]. Its first copy ships inside Sieve, so it works offline
from the start. Refresh downloads the latest copy.

To add your own list, paste an `https` URL and click **Add**, or click
**Upload** and pick a file. Choose Block or Allow first. Allow lists win
over block lists.

A list is plain UTF-8 text in one of two forms:

```text
# One host per line
ads.example.com
tracker.example.net
```

```text
# Hosts-file lines: the first word, an IP address, is skipped
0.0.0.0 ads.example.com
127.0.0.1 metrics.example.org stats.example.org
```

- Text after `#` is a comment. Words without a dot are skipped.
- An entry covers its host and every subdomain. `example.com` covers
  `www.example.com`, but not `notexample.com`. No wildcards are needed.
- JSON, CSV, and Adblock syntax such as `||example.com^` do not work.
- A list may hold up to 16 MB.

> [!TIP]
> [Peter Lowe's list][yoyo] works when served as plain text. Use the
> link below.
>
> ```text
> https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext
> ```

### Rules

![The Rules screen](docs/images/rules.jpg)

Rules is a grid. Each row is an app, or an app and one host. The columns
are **Always**, then one per profile. Each cell has ✓ Allow and ✕ Block.

- Click ✓ or ✕ to set a cell. Click it again to clear it.
- A profile cell beats **Always** while that profile is active. An empty
  profile cell follows **Always**.
- Each row shows its hits and its last hit.
- The trash button deletes the row's rules. The app's history stays.

Sieve flags rules that can never fire:

| Flag | Meaning |
| --- | --- |
| App is gone | The app is no longer on the Mac. |
| App is blocked | A host rule under a block on the whole app. |
| On a block list | A list blocks this host already. |
| Parent domain rule | A rule for a parent domain does the same. |

### Profiles

![The Profiles screen](docs/images/profiles.jpg)

A profile is a set of rules for a place or a time. It is active on its
network, or during any of its time blocks.

- **Use this network** saves the network the Mac is on now. Sieve knows
  it by its router's IP and MAC address. No Location permission is
  needed.
- **Add time** adds a block of weekdays with a start and an end. A block
  ends before midnight. For a night, use two blocks.
- One profile is active at a time: the first in the list that matches.
  Order matters.

### Menu bar

![The menu bar window](docs/images/menu.jpg)

Click the Sieve icon in the menu bar for the live rate, the five busiest
apps with a switch each, and blocked connections for the last seven
days.

### Recipes

**Block one domain for one app.** Open the app in App X-Ray, find the
host, and click Block. The app stays online. The rule covers the
host's subdomains.

**Keep a backup app off your phone's hotspot.** In Profiles, create
"Hotspot" and click **Use this network** while on the hotspot. In
Rules, click ✕ in the Hotspot column of the backup app. Its ✓ in
**Always** keeps it online everywhere else.

**Allow an app only at work hours.** Create a profile "Work" with a time
block, Monday to Friday, 09:00 to 17:00. Block the app in **Always** and
allow it in the Work column.

**Sort out a new Mac.** Stay in Quiet mode for a few days. Then open
Apps, go through **Undecided**, and block or allow each app. Switch to
Ask mode once the list is empty.

## 3. Under the hood

### How it fits together

```mermaid
flowchart LR
  apps["Apps on the Mac"] -->|new connection| net["macOS networking"]
  net -->|"app token, host, address"| ext["SieveExtension<br/>root, sandboxed"]
  ext -->|"allow, drop, or pause"| net
  ext <-->|"XPC: config, stats, prompts"| app["Sieve.app<br/>window and menu bar"]
  app -->|"https list downloads"| web[("list servers")]
  ext --- disk[("config.json, stats.json, lists")]
```

- The filter is an `NEFilterDataProvider`, packaged as a system
  extension. It sees each new outgoing flow, never its contents.
- The extension owns all state. The app is a client over one XPC Mach
  service, and the extension accepts only the Sieve app signed by the
  same team.
- The app downloads lists. The extension has no network access of its
  own.
- Swift 6 and SwiftUI. No third-party packages.

### How Sieve decides

The extension decides each new connection from memory, in this order.
The first match wins.

```mermaid
flowchart TD
  start(["New connection"]) --> off{"Mode is Off?"}
  off -- yes --> allow1["Allow"]
  off -- no --> blocked{"App blocked or over its limit?"}
  blocked -- yes --> drop1["Drop"]
  blocked -- no --> hostRule{"App has a rule for this host?"}
  hostRule -- yes --> useRule["Use that rule"]
  hostRule -- no --> allowList{"Host on an allow list?"}
  allowList -- yes --> allow2["Allow"]
  allowList -- no --> blockList{"Host on a block list?"}
  blockList -- yes --> drop2["Drop"]
  blockList -- no --> appAllow{"App has an allow rule?"}
  appAllow -- yes --> allow3["Allow"]
  appAllow -- no --> apple{"Apple system code?"}
  apple -- yes --> allow4["Allow"]
  apple -- no --> ask{"Mode is Ask?"}
  ask -- no --> quiet["Allow and record"]
  ask -- yes --> running{"Sieve app running?"}
  running -- yes --> prompt["Pause and prompt"]
  running -- no --> drop3["Drop"]
```

- A rule of the active profile beats an **Always** rule for the same
  app and host.
- A host rule covers the host and its subdomains. The most specific
  rule wins, so a block on `example.com` and an allow on
  `cdn.example.com` allow the CDN and block the rest.
- The extension fails open: if it cannot decide, it allows. The one
  exception is Ask mode with no Sieve app running.
- A list check walks the host and each parent domain. On the 78,217
  entries of Tracker Shield it takes about 1.2 µs per list, about 0.1 %
  of one core at 200 new connections a second.

### How Sieve names an app

Each connection carries an audit token for its process. Sieve reads the
code signature of that process and gives the app a key:

| Code | Key | Example |
| --- | --- | --- |
| Signed by a developer | `TEAMID.identifier` | `ABCDE12345.com.example.app` |
| Signed by Apple | The identifier | `com.apple.Safari` |
| Anything else | The path | `/opt/homebrew/bin/wget` |

- A Team ID counts only when the signing certificate carries it. A
  copied or altered app gets its own key, not the original's rules.
- Code inside an app bundle counts as the outermost app, when the same
  signer signed both.
- A path key also holds the hash of the running code. An Allow rule for
  it counts only for that code, so a changed binary asks again.
- Apple's daemons are allowed with no rule. Apple's command-line tools,
  such as `curl`, `ssh`, and `osascript`, are not: any app can run them,
  so they prompt and take rules like any app.

### Where data lives

The filter runs as `root` in its own sandbox. Its files sit in its
container:

```text
/var/root/Library/Containers/me.pilinux.Sieve.SieveExtension/Data/
└── Library/Application Support/me.pilinux.Sieve/
    ├── config.json     mode, rules, lists, limits, profiles
    ├── stats.json      hosts, bytes, blocked counts, rule hits
    └── lists/<id>.txt  a copy of each list
```

Read them with `sudo`:

```sh
dir="/var/root/Library/Containers/me.pilinux.Sieve.SieveExtension/Data"
sudo ls -l "$dir/Library/Application Support/me.pilinux.Sieve"
```

How long Sieve keeps its stats:

| Data | Kept |
| --- | --- |
| Hosts of an app | 31 days since last seen, at most 1,000 |
| Daily bytes and blocked counts | 31 days |
| An app with no rule and no limit | 31 days since last seen |
| Hits of a rule | Until the rule is deleted |

If `config.json` cannot be read, Sieve moves it aside as
`config.json.broken`, starts with defaults, and shows a notice. **Save a
copy** keeps the file for you. **Discard** deletes it.

### Limits

- **No host name, no domain match.** Apps that look up names
  themselves, such as Chrome with secure DNS, give only an IP address.
  Domain rules and lists cannot match. App rules still apply.
- **Web pages show as WebKit.** Safari and every app with a web view
  load pages through `com.apple.WebKit.Networking`. No public API names
  the app behind it, so one rule for it covers all of them. A rule for
  Safari does not cover its pages.
- **DNS leaves through the system.** Name lookups go through
  `mDNSResponder`, not the app. A blocked app can still look up names.
- **New connections only.** A new rule, list, profile, or limit acts on
  new connections. Open ones run until they close.
- **Shared tools.** A rule for `curl` covers every app that runs `curl`.
  An allowed interpreter, such as `python3`, runs any script with its
  rules.
- **Networks can be copied.** A network is known by its router's IP and
  MAC address. A hostile network that copies both gets the profile of a
  trusted one. Networks with IPv6 only cannot be a profile's network.
- **Changing code asks again.** An update of a tool with no verified
  signer, such as a Homebrew binary, changes its code. Ask mode prompts
  for it once more. Unsigned code prompts on every connection.
- **Outgoing only.** The macOS firewall covers incoming connections.
- **Not yet tested:** iCloud Private Relay may hide Safari traffic from
  the filter.

### Questions developers ask

#### Why a content filter, not a VPN or packet tunnel?

`NEFilterDataProvider` decides per flow and hands the filter the app's
audit token. It routes no traffic and reads no contents, so it runs
next to a VPN. A packet tunnel would see packets without the app behind
them.

#### Why does Ask mode drop connections when the app is closed?

The prompt lives in the app. If the extension allowed unknown apps
while the app was gone, any program could quit Sieve and get through.
Quiet mode never drops for this reason.

#### Why can a blocked app still look up names?

macOS resolves names in `mDNSResponder`, a system daemon. The filter
sees that daemon's connections, not the app's. Blocking it would break
every app.

#### Why do open connections survive a new rule?

The filter decides when a flow starts. Cutting a flow later would mean
reading the data of every allowed connection, which Sieve never does.

#### How does Sieve know a network without Location permission?

The extension watches `SCDynamicStore`. macOS gives each IPv4 network a
`NetworkSignature` with the router's IP and MAC address. Sieve stores
the whole string, so two homes that both use `192.168.1.1` stay apart.

#### Where does Tracker Shield load from?

The first copy ships in the extension bundle as `trackers.txt`. After
the first Refresh, the extension loads `lists/tracker-shield.txt` from
its data folder instead.

#### How do I build Sieve myself?

You need Xcode 27 and a paid Apple Developer Program membership. The
Network Extension and System Extension capabilities require it.

1. Clone the repo and open `Sieve.xcodeproj`.
2. In both targets, set your team under **Signing & Capabilities**.
3. Change the bundle IDs `me.pilinux.Sieve` and
   `me.pilinux.Sieve.SieveExtension`, and the app group, to your own.
   The code names them in `Sieve/Filter.swift`,
   `SieveExtension/FilterDataProvider.swift`, and
   `SieveExtension/Info.plist`.
4. Build, copy to `/Applications`, and open:

   ```sh
   xcodebuild -scheme Sieve -destination 'platform=macOS,arch=arm64' \
     -derivedDataPath build -quiet \
     CURRENT_PROJECT_VERSION="$(date +%s)" build
   ditto build/Build/Products/Debug/Sieve.app /Applications/Sieve.app
   open /Applications/Sieve.app
   ```

System Integrity Protection stays on. macOS loads the extension only
from `/Applications`, and replaces it only when the build number
changes, hence the fresh `CURRENT_PROJECT_VERSION`. Check the state
with:

```sh
systemextensionsctl list
/usr/bin/log show --last 5m --predicate 'subsystem BEGINSWITH "me.pilinux"'
```

App and host names show as `<private>` in the log, by design.

#### How do I run the tests?

```sh
xcodebuild -scheme Sieve -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build -quiet test
swift format lint -r Sieve Shared SieveExtension SieveTests
```

Tests cover the pure logic in `Shared/`: the verdict order, list
parsing and matching, rule flags, grades, data limits, profiles, stats
limits, and decoding of saved files.

### Project layout

| Folder | Holds |
| --- | --- |
| `Sieve/` | The app: window, menu bar, prompts, list downloads |
| `SieveExtension/` | The filter: verdicts, app identity, storage |
| `Shared/` | Models, verdict logic, list parser, XPC protocol |
| `SieveTests/` | Swift Testing tests for `Shared/` |
| `docs/images/` | The pictures in this README |

### Credits and licence

- [Steven Black's unified hosts][hosts], MIT License, is the Tracker
  Shield list. Its licence ships next to it in the extension.
- Aileron, by Sora Sagano, CC0 1.0, is the app's font.
- [LuLu][lulu] and [Pi-hole][pihole] shaped the feature set.

Sieve: a per-app firewall for macOS with Ask and Quiet modes and tracker
blocking.
Copyright (C) 2026 Mahir Hasan

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation, version 3.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
Public License for more details.

You should have received a copy of the GNU General Public License along
with this program. If not, see <https://www.gnu.org/licenses/>.

[appstore]: https://apps.apple.com/app/idAPP_ID
[hosts]: https://github.com/StevenBlack/hosts
[yoyo]: https://pgl.yoyo.org/adservers/
[lulu]: https://objective-see.org/products/lulu.html
[pihole]: https://pi-hole.net
[badge-macos]: https://img.shields.io/badge/macOS-26.6%2B-black
[badge-arch]: https://img.shields.io/badge/Apple%20silicon-tested-brightgreen
[badge-swift]: https://img.shields.io/badge/Swift-6-orange
[badge-licence]: https://img.shields.io/badge/licence-GPL--3.0--only-blue
