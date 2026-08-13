# Working on this project

Read `README.md` first: it says which layer enforces what, and which layers look like
boundaries but are not.

## Invariants

- **Each wrapper hardcodes its gog command.** Removing it, or letting the client argv
  name a command, silently widens the key to everything the profile and token permit.
  Every wrapper states this contract in its header; keep the header true.
- **Nothing safety-relevant goes in `gog.env`.** It holds defaults a command line can
  override. Scope belongs in the wrapper, policy in the baked profile.
- **`SKILL.md` examples match what the wrappers hardcode.** They ship in the same
  change, or the agent's next call fails with `unexpected argument`.
- **The launcher names are documentation, not enforcement.** Never cite a file name as
  the reason something is impossible.

## Verifying a change

Run through the launchers as the agent account. Building an ssh command by hand, or
calling a wrapper directly as the owner, tests a simulation of the path rather than the
path, and will not catch a broken forced command, key or `authorized_keys` line.

Use `--dry-run` for anything that writes. If a check does change the mailbox, restore
the previous state in the same session and say so.

A claim about what the agent can or cannot reach is only worth writing down once the
attempt has been made and its output read: profiles, tokens and wrappers each refuse in
a different way, and only the message says which one acted.

## Deploying

Owner-side files (wrappers, `Makefile`, `gog.env.example`) and agent-side files
(launchers, `SKILL.md`) install into different directories, and a wrapper change plus a
`SKILL.md` change must land together. After deploying, re-run the verification commands
in `README.md`; after changing a binary, rebuild with `make update` rather than copying
a binary in.

## Keeping this directory honest

These files are the working copies. After any deploy, the copies here and the installed
copies should be byte-identical — compare them rather than assuming. The launchers are
the exception: they ship as `.example` files, so the installed copy is that file with
`SSH_TARGET_HOST` and `KEY_FILE_PATH` set, and a change to one means editing both.
The profiles under `safety-profiles/` are deployed beside the Makefile, not into the
gogcli checkout, and the binaries must be rebuilt after any change to them. Delete superseded
variants instead of leaving them beside the live ones; a stale copy of a security
wrapper is worse than no copy.
