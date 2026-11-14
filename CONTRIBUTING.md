# Contributing to Sieve

Thank you for considering a contribution to Sieve. Bug reports, ideas,
documentation, and code all make it a better firewall.

Following these guidelines shows that you respect the time of the
maintainer, who runs the project alone. In return, the maintainer
respects yours: each issue and pull request gets an answer, and help to
get it merged.

## What we look for

- Bug reports, with the steps that show the bug.
- Fixes for open issues.
- Improvements to the README and the other documentation.
- Tests for the logic in `Shared/`.
- Ideas that fit the scope below.

## What we do not accept

- Support questions in the issue tracker. Read the README first. If it
  does not answer the question, open an issue that names the gap in
  the documentation.
- Features outside the scope of Sieve. See
  [Suggest a feature](#suggest-a-feature).
- Third-party packages. Sieve uses Apple frameworks only.
- Translations. Sieve is in English only for now.
- Code under the GPL, LGPL, or AGPL taken from other projects. See
  [Licence of contributions](#licence-of-contributions).

## Ground rules

- Be respectful and stay on topic. The maintainer may edit, lock, or
  remove unkind or off-topic comments.
- Open an issue before a large change, and agree on the approach
  before you write much code.
- Keep one change per pull request.
- Target macOS 26.6 or later. Do not add code for older macOS.
- Use public APIs only. The Mac App Store rejects private ones.
- Never write a host, IP address, URL, app path, or a name the user
  typed into the error log. The log must stay safe to share.

## Your first contribution

Look for issues labelled `good first issue`. They need a small change
and a test or two. Issues labelled `help wanted` need more work.

New to pull requests? GitHub's guide [Contributing to a project][gh-pr]
shows each step.

## Getting started

1. Fork the repository and create a branch from `main`.
2. Build Sieve as "How do I build Sieve myself?" in the
   [README](README.md#how-do-i-build-sieve-myself) shows. You need
   Xcode, a paid Apple Developer Program membership, and Node.js for
   the Markdown check.
3. Make the change. Add or update tests for logic in `Shared/`.
4. Run the checks. Each must pass with no warnings:

   ```sh
   xcodebuild -scheme Sieve -destination 'platform=macOS,arch=arm64' \
     -derivedDataPath build -quiet test
   swift format lint -r Sieve Shared SieveExtension SieveTests
   npx --yes markdownlint-cli2 "**/*.md" "#build"
   ```

5. Open a pull request. Say what it changes and why, and link the
   issue it closes.
6. Sign the [Contributor License Agreement](CLA.md) when the bot asks.

Every pull request needs a signed CLA, even a one-line fix.

## Report a security issue

If you find a security vulnerability, do not open an issue. Use
**Report a vulnerability** on the repository's Security tab. It
reaches the maintainer only.

Ask yourself two questions. Can an app get past a rule that blocks
it? Can a program change Sieve's rules or read its data without the
user? If the answer to either is yes, report it as a security issue.
If you are not sure, report it that way too.

## Report a bug

Open an issue, and answer these questions:

1. Which macOS version and Mac model do you use?
2. Which Sieve version do you use? See Sieve > About Sieve.
3. Which mode is on: Off, Ask, or Quiet?
4. What did you do?
5. What did you expect to see?
6. What did you see instead?

If Sieve logged an error, attach a copy of the error log: open
Diagnostics and press Save a copy. The file holds no host, IP address,
URL, app path, or name you typed. Read it before you attach it.

## Suggest a feature

Sieve controls the outgoing connections of each app, blocks trackers,
and shows what each app contacts. Everything stays on the Mac. Sieve
stays small, so these ideas are out of scope:

- incoming connections: the macOS firewall covers them
- accounts, paid tiers, licence keys, or any server
- analytics, or anything that sends data off the Mac
- temporary rules, such as "once" or "until quit"

To suggest a feature, open an issue. Describe what you want to do, why
you need it, and how it might work.

## Code review process

The maintainer reviews every pull request. Expect a first answer
within two months. After a review, the pull request waits for your
reply. If it gets no activity for six months, the maintainer may close
it. You can reopen it at any time.

A pull request is merged when the review is done, the CLA is signed,
and the checks in step 4 of [Getting started](#getting-started) pass.
The maintainer runs them again before the merge.

## Community

All discussion happens in GitHub issues and pull requests. Sieve has
no chat or mailing list.

## Conventions

### Code style

`.swift-format` sets the format. Write a comment only for what the code
cannot say: the reason, or a platform constraint. Use `///` only on
declarations that are not `private`.

### Commit messages

The first line is the summary: `type: summary`, in the imperative,
starting in lower case, at most 50 characters. Types: `feat`, `fix`,
`docs`, `refactor`, `style`, `test`, `ci`, `chore`.

For more than the summary can say, leave a blank line and add a
description. It has no length limit. Explain what changed and why,
not how. Wrap its lines at 72 characters.

```text
fix: keep Ask mode client after extension restart

The extension learns its Ask mode client from the app's first XPC
message. After the extension restarted, the app sent none, so new
apps no longer prompted. The app now sends a message whenever the
connection drops, and retries once a second until the extension
replies.
```

### Labels

Issues use GitHub's default labels: `bug`, `enhancement`,
`documentation`, `question`, `good first issue`, `help wanted`,
`duplicate`, `invalid`, and `wontfix`.

## Licence of contributions

Sieve is free software under the GNU General Public License, version 3
only ([LICENSE](LICENSE)). Every contribution stays available under it,
in the public source.

Sieve also ships on the Mac App Store. Apple's terms add limits that
GPL-3.0 does not allow on code from other people. So before your first
pull request is merged, you sign the
[Contributor License Agreement](CLA.md). In short:

- You keep the copyright in your work.
- You let the maintainer ship it under other terms as well, such as
  the Mac App Store's.
- You confirm that the work is yours to give.

A bot comments on your first pull request with a sentence to post.
Post it once, and it covers all your later pull requests.

Bring in code from elsewhere only when it is your own, or under a
licence such as MIT, BSD, or Apache-2.0 that allows both GPL-3.0 and
App Store use. Keep its notice, and name it in the pull request. Sieve
does not accept code taken from other projects under the GPL, LGPL,
or AGPL.

---

This guide follows the structure of the
[contributing template][template] by Nadia Asparouhova, released under
[CC0 1.0][cc0].

[gh-pr]: https://docs.github.com/en/get-started/exploring-projects-on-github/contributing-to-a-project
[template]: https://github.com/nayafia/contributing-template
[cc0]: https://creativecommons.org/publicdomain/zero/1.0/
