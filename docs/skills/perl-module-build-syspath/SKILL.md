---
name: perl-module-build-syspath
description: >-
  Use when a Perl application or distribution must install or locate
  configuration, templates, state, cache, log, lock, or served files outside
  lib/, including choosing how to do so, or when a Build.PL uses
  Module::Build::SysPath or a *::SPc module exists. Not for Dist::Zilla or
  ExtUtils::MakeMaker builds, or read-only data of reusable CPAN libraries
  (use File::ShareDir).
---

# Module::Build::SysPath file installation

Ship non-code files in the distribution so that a checkout uses them in
place and `./Build install` puts them into FHS directories chosen by
`Sys::Path`. Code always asks `<Dist>::SPc` for a directory and never
hard-codes `/etc` or `/var`.

## Decide fit

Use it for system-installed applications or services that have config, state,
or logs. For read-only data of a reusable library, use `File::ShareDir`. For
`dist.ini` builds, follow the Dist::Zilla workflow (a `perl-dzil` skill, if
available).

## Procedure

1. Pick a path type for each kind of file:

   | Files | Type | Checkout dir | Installed (`/usr` perl) |
   | --- | --- | --- | --- |
   | Admin-edited config | `sysconfdir` | `etc/` | `/etc` |
   | Read-only data, templates | `datadir` | `share/` | `/usr/share` |
   | Persistent app state | `sharedstatedir` | `var/lib/` | `/var/lib` |
   | Logs | `logdir` | `var/log/` | `/var/log` |
   | Cache | `cachedir` | `var/cache/` | `/var/cache` |
   | Served content | `srvdir` | `srv/` | `/srv` |

   Also available: `lockdir`, `spooldir`, `rundir` (`/var/<kind>`), `webdir`
   (`/var/www`), `docdir`, and `localedir`. Put files into a dist-named
   subdirectory, for example `etc/acme-notes/notes.ini`, because the whole
   tree installs into a shared system directory. Drop-in directories such as
   `etc/cron.d/` are the exception.
1. Create `lib/<Dist/Path>/SPc.pm`. The package is `module_name` with `-`
   replaced by `::` and with `::SPc` appended. Copy the
   [example](references/example.md) and keep only the types in use.
1. In `Build.PL`, use `Module::Build::SysPath->new(...)` and add
   `Module::Build::SysPath` to `configure_requires` and `build_requires`.
   For custom actions, use `Module::Build::SysPath->subclass(code => ...)`
   and call `$self->SUPER::ACTION_install` from an overridden install.
1. At runtime, build paths from the accessors:
   `File::Spec->catfile(Acme::Notes::SPc->sysconfdir, 'acme-notes', 'notes.ini')`.
1. Verify with `perl Build.PL && ./Build && ./Build test`, then run
   `./Build install --destdir=/tmp/stage` and inspect the staged tree and the
   staged `SPc.pm`. Run a real install only when the user authorizes it.
1. List every shipped file, `.exists` markers included, in `MANIFEST`. From
   0.20 on, unlisted files are not installed.

## SPc.pm contract

On install, `ACTION_install` rewrites the installed `SPc.pm`. If this
contract is broken, the install dies.

- `_path_types` lists the accessors to rewrite. Include `prefix` and
  `localstatedir` when other accessors derive from them. Those two are never
  install targets.
- Each listed accessor must be exactly one simple sub without nested braces,
  such as
  `sub logdir { File::Spec->catdir(__PACKAGE__->localstatedir, 'log') };`. The
  rewrite replaces it with a quoted literal path.
- Lines ending in `# remove after install` are dropped, for example
  `use Sys::Path; # remove after install`. All other lines, including
  comments, ship unchanged. Write comments that stay true after install.
- Unlisted helpers such as `tmpdir` keep working by deriving from the
  rewritten accessors.

## Install rules

- `cachedir`, `logdir`, `spooldir`, `rundir`, `lockdir`, and `sharedstatedir`
  start empty. An empty `.exists` file creates its directory; the marker itself
  is not installed. To install a seed file, pass
  `sharedstatedir_files => { 'var/lib/acme-notes/seed.json' => 1 }` (the key is
  dist-relative) to `new()`. Every install overwrites the seed with the shipped
  copy, so runtime changes to it are lost. Either create such files at runtime
  or also list them in `conffiles`.
- Dot directories and dot files other than `.exists` are skipped unless
  listed in `<type>_files`, for example
  `webdir_files => { 'www/.htaccess' => 1 }`. Versions up to 0.19 never
  install dot files, even when listed. With those versions, require 0.20,
  ship a non-dot name, or create the file at runtime.
- When `MANIFEST` exists (0.20+), only files listed in it are installed,
  `.exists` markers included. `perl Build.PL` warns
  `'<file>' is not listed in MANIFEST and will not be installed` for each
  skipped file, except files matching `MANIFEST.SKIP`, which are skipped
  silently. Treat these warnings as errors unless the file is meant to stay
  out of the install. A file kept out of the tarball by `MANIFEST.SKIP`, such
  as an unpublished key, is not installed from a checkout either; deploy it
  outside the build. Up to 0.19, every file found on disk is installed.
- Every file under `sysconfdir`, plus files listed in `conffiles`, is a
  conffile. A system copy that was not edited locally is replaced on upgrade. A
  locally edited copy is never overwritten silently. The shipped version is
  installed as `<file>-spc`. When the shipped copy also changed, the install
  first prompts. If the user accepts the new version, the edited file is renamed
  to `<file>-old` instead. If that `-old` file already exists, the install dies,
  so remove it after merging. Unattended installs (`PERL_MM_USE_DEFAULT`, or no
  terminal and empty stdin) keep the edited copy. A system file without a
  recorded checksum counts as locally edited. Checksums are stored in
  `Sys::Path->sharedstatedir/syspath/install-checksums.json`. With `--destdir`,
  there is no prompt and no checksum, so a staged install cannot test upgrade
  behavior.
- After install, `sysconfdir` and `sharedstatedir` files are chmod 0644.
  Ownership is never changed. Grant the runtime user write access outside the
  build, for example in packaging, provisioning, or docs.

## Pitfalls

- Target directories come from the `Sys::Path` installed for the perl that
  runs `Build.PL`. By default, a `/usr` perl gives FHS paths, and perlbrew
  and local perls install under their own prefix. The `Sys::Path` installer
  can override each path. Check with
  `perl -MSys::Path -E 'say Sys::Path->sysconfdir'`.
- `perl Build.PL` scans the path-type directories on disk and stores the file
  list. Rerun it after adding files, and add new files to `MANIFEST`. Without
  a `MANIFEST`, stray files such as editor backups are installed too.
- During development the app writes into `var/` in the checkout. Ignore those
  runtime files in VCS and in `MANIFEST.SKIP`, and keep the `.exists` markers
  and seeds, for example `^var/log/acme-notes/(?!\.exists$)`.
- `Sys::Path` is needed only in a checkout, because the installed `SPc.pm` no
  longer loads it. `Module::Build::SysPath` already pulls it in, so it needs no
  runtime `requires` entry.
- Every file found under a listed accessor's directory must lie inside the
  distribution root, or `perl Build.PL` dies. Point accessors at directories
  inside the checkout.
