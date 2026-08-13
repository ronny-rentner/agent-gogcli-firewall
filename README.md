# agent-gogcli-firewall

**A simple protection layer for [gogcli](https://github.com/openclaw/gogcli).** Gradually
whitelist and filter what an AI agent may do with your Google services: Gmail, Google
Drive, Google Calendar, and the rest.

With the outlined approach, your agent never needs your real credentials or even OAuth keys.
Instead, it will access gogcli via an SSH bridge which allows fine grained control of which
commands and subcommands with which flags exactly the agent is allowed to run. 

Out of the box, this project delivers two recipes for reading emails and for writing drafts:

```console
agent$ ./gmail-readonly messages search 'is:unread' --max 3
agent$ ./gmail-draft --to bob@example.com --subject Hi --body-file - <<'EOF'
Drafts only. You send it yourself from Gmail.
EOF
```

## Features

- **No secret on the agent's host.** The OAuth token and keyring stay with you. The
  agent holds only ssh keys, and each key can run exactly one command you chose.

- **Rules baked into the binary.** Command allow/deny lists and locked (enforced) flags are
  compiled in at build time so the agent can never override or forget them.

- **Revocation is instant.** Delete a key, stop sshd, or (across hosts) pull the
  network. Nothing to clean up on the agent's side, because nothing was ever there.

- **Small and readable.** A few lines of easy-to-extend shell code over
  [gogcli](https://github.com/openclaw/gogcli) and OpenSSH, no daemon of its own.

## Concept

gogcli uses OAuth tokens but those actually do work with any HTTP client. Restricting what
gogcli may do buys nothing if the agent can read the token and use it for something else.
So the line to hold is what gogcli can do *and* who may touch the token.

Holding that line is the hard part, because the agent is what drives gogcli. So the agent
works from the outside, on a separate account it cannot log into. Crossing between
accounts is normally sudo's job, but an agent already inside a sandbox usually cannot
elevate at all, so it crosses a different way: a single ssh key whose forced command runs
one fixed program and nothing else. That program runs gogcli inside bubblewrap, which
gives the process the token and a scratch area but no path that persists for the agent to
read afterward and no escape into another command. Agent input can steer gogcli; it
cannot turn the token-bearing process into a way out.

The result is the split you want: gogcli can use the token, the agent cannot. It can ask
gogcli to read a message or write a draft, and it can never lift the token and use it
somewhere else.

### What holds the line

The concrete layers, from the agent inward to the token:

1. **A fixed command.** The agent's keys run wrappers, only from the address you allow,
   and those wrappers run one fixed gog command each.
2. **A baked profile.** Allowed commands, subcommands and locked flags are compiled into
   the binary, so the command line cannot widen or unset them.
3. **No shell sees the agent's input.** The wrapper rebuilds the arguments from bytes and
   passes them to a binary, quoted, so `; rm -rf ~` is a string gog rejects, not a command
   that runs (see [The argv transport](#the-argv-transport)).
4. **bubblewrap.** gog runs with the filesystem read-only except a scratch area, so agent
   input cannot drop the token, or anything, where the agent can read it later.
5. **The token's scopes.** Past everything above, the token still reaches only the Google
   services its scopes cover; anything outside them returns `403`.

## Recipes

The project ships two example recipes:

| recipe           | runs                  | the agent can                                  |
|------------------|-----------------------|------------------------------------------------|
| `gmail-readonly` | read-only `gmail`     | search and read messages, download attachments |
| `gmail-draft`    | `gmail drafts create` | create a new draft                             |


Each recipe comes with its own wrapper script and uses its own security profile. Those profiles
bake in the allowed commands and the enforced flags that matter when an agent is driving, like
`--sanitize-content`, `--wrap-untrusted` and `--json`.

See [`safety-profiles/`](safety-profiles/) for more details.

### Adding a new recipe

A new capability is a new recipe. To add one:

1. Generate a new SSH key pair.
2. Add an `authorized_keys` line pinning that key to the new wrapper.
3. Copy an existing wrapper and change the gog command it hardcodes.
4. Copy an existing profile and set the commands and locked flags it allows.
5. Rebuild the binaries with `make`.
6. Roll the wrapper, profile and key line out to the two accounts, as in [Install](#install).

Step 3 defines the capability: hardcode `gmail messages modify` to label mail, `gmail
archive` to archive it, or `gmail trash` to clear spam.

A wrapper fixes the command, not its arguments. To narrow the arguments, lock a boolean in
the profile with `locked-flags`, or have the wrapper inspect the decoded argv and reject
what it should not allow (insist a query is exactly `in:spam`, refuse any `--out`). A flag
the wrapper passes does not constrain the agent, because its argv is appended after and a
repeated flag takes its last value.

A capability the shipped profiles forbid needs its own binary. `gmail trash` is refused by
`agent-safe-locked`, so a spam-clearing recipe builds against a profile that allows exactly
that command. Binaries, profiles and keys stay independent, so adding one never widens
another.

Nothing here is Gmail-specific. A wrapper hardcoding `calendar events` or `drive ls` grants
those the same way.

## Install

The setup has two accounts: `owner` (holds the credential) and `agent` (runs the AI).
They can be two users on one host, or two hosts; the steps are the same, and the paths
below are examples. The owner side needs Go and `bubblewrap`; the agent side needs `jq`.

### Owner side

**1. Build the binaries.** Needs Go. The first `make` clones gogcli beside the Makefile;
use `make GOGCLI=/path/to/gogcli` to point at an existing checkout.

```bash
cd agent-gogcli-firewall
make                                    # builds gog, gog-readonly-locked, gog-agent-safe-locked
```

**2. Authorize Gmail once**, with the plain `gog` binary. Create an OAuth client (Desktop
app) in a Google Cloud project with the Gmail API enabled, then:

```bash
./gog auth credentials set <client_secret.json>
./gog auth add you@gmail.com            # opens a browser, stores a refresh token
```

**3. Write `gog.env`.** Copy the template and set the account, a keyring password, and
the data/config dirs:

```bash
cp gog.env.example gog.env && chmod 600 gog.env
$EDITOR gog.env
```

**4. Lock the owner directory** so the agent account cannot read the keyring or the
credential. This is what makes the token unreachable, not any file mode on the binaries:

```bash
chmod 700 ~                             # owner home not traversable by the agent user
```

**5. The owner directory now holds everything.** The wrappers shipped with the project,
`make` built the `gog-*-locked` binaries beside them, and step 3 wrote `gog.env` there.
Each wrapper finds its binary, `gog.env`, and data next to itself, so nothing is installed
elsewhere. This directory is what the forced command points at in step 8.

### Agent side

**6. Generate one key per capability**, no passphrase (the calls are non-interactive):

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/gog_readonly
ssh-keygen -t ed25519 -N '' -f ~/.ssh/gog_draft
```

**7. Pin the owner's host key** so the first non-interactive call does not fail:

```bash
ssh-keyscan <owner-host> >> ~/.ssh/known_hosts
```

**8. Authorize each key to exactly one wrapper.** Append to the **owner's**
`~/.ssh/authorized_keys`, one line per key. This line is the boundary, so copy it
exactly (`restrict` first, correct `command=`, `from=` matching where the agent connects
from):

```
restrict,from="127.0.0.1,::1",command="/home/owner/agent-gogcli-firewall/gog-readonly-forced" ssh-ed25519 AAAA…readonly
restrict,from="127.0.0.1,::1",command="/home/owner/agent-gogcli-firewall/gog-draft-forced" ssh-ed25519 AAAA…draft
```

For two hosts, set `from=` to the agent host's address instead of loopback.

**9. Install the recipe scripts and the skill.** Copy each recipe script without the
`.example` suffix and set `SSH_TARGET_HOST` and `KEY_FILE_PATH` at the top:

```bash
cp gmail-readonly.example gmail-readonly && $EDITOR gmail-readonly
cp gmail-draft.example    gmail-draft    && $EDITOR gmail-draft
install -m 755 gmail-readonly gmail-draft ~/gmail/
install -m 644 SKILL.md ~/gmail/
```

A wrapper change and a `SKILL.md` change ship together: the skill's examples are written
for the command each wrapper hardcodes, and the previous form fails with
`unexpected argument`.

## Verify

Run the recipe scripts as the **agent** account. Testing by hand-building an ssh command
checks a simulation of the path, not the path:

```bash
agent$ ./gmail-readonly messages search is:unread --max 1     # → JSON
agent$ echo body | ./gmail-draft --dry-run --to a@b.com --subject t --body-file -   # → gmail.drafts.create plan, nothing created
agent$ ./gmail-readonly drive ls                              # → unexpected argument drive
```

## Files

| file | side | purpose |
|---|---|---|
| `gmail-readonly.example`, `gmail-draft.example` | agent | the recipe scripts the AI runs; copy without the suffix and set two variables |
| `SKILL.md` | agent | what the AI loads to learn the two commands |
| `gog-readonly-forced`, `gog-draft-forced` | owner | ssh forced commands; hardcode the gog command, apply bubblewrap |
| `safety-profiles/*.yaml` | owner | command rules and locked flags baked into each binary |
| `Makefile` | owner | builds the baked binaries from a gogcli checkout |
| `gog.env.example` | owner | template for `gog.env` (account, keyring, paths) |

The profiles live here, not in the gogcli checkout: they are this project's policy, and
upstream ships only unlocked ones, so a plain clone could not build these binaries.

## License

[MIT](LICENSE)

