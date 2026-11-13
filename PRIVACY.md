# Sieve privacy policy

Effective 13 November 2026.

Sieve collects no data. It has no account, no server, no analytics, no
ads, and no third-party code. Nothing Sieve records leaves your Mac.

## What the filter sees

Sieve's filter checks each new outgoing connection. For each one it
sees:

- the app that opens it, by its path and code signature
- the host name, if the app gave one
- the remote IP address
- the number of bytes sent and received

It never reads what a connection carries.

## What Sieve stores on your Mac

- Your settings: mode, rules, lists, data limits, and profiles. A
  profile that follows a network keeps that network's router address.
- Per app: its path, the hosts it contacted, and its byte counts, for
  the last 31 days.
- Blocked connections per day, and the hits of each rule.
- A copy of each list you add.

The filter keeps these files in its own folder, readable only by an
administrator. The system log shows app and host names as private, so
they stay out of diagnostic reports.

## Network requests

Sieve connects to the internet only to download lists:

- Tracker Shield, from `raw.githubusercontent.com`.
- Each list URL you add.

It does so only when you add a list or press Refresh. The server of
each list sees your IP address, as with any download. GitHub's privacy
policy covers `raw.githubusercontent.com`.

## Deleting your data

- To clear one app's history, open it in App X-Ray and clear it.
- To delete a list, delete it under Lists.
- To remove everything, drag Sieve to the Trash and let macOS remove
  the extension. Then delete the filter's folder in
  `/var/root/Library/Containers/me.pilinux.Sieve.SieveExtension`.

## Changes

Changes to this policy appear in this file, with a new effective date.
The file's history on GitHub shows every change.

## Contact

Open an issue at <https://github.com/pilinux/sieve/issues>.
