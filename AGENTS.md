# Repository Instructions

`README` is generated from the POD in `lib/Module/Build/SysPath.pm`. Do not
edit `README` directly. Update the main module, then regenerate `README` with:

```sh
perl Build.PL && ./Build distmeta
```

The agent skill in `docs/skills/perl-module-build-syspath/` restates install
behavior of `lib/Module/Build/SysPath.pm` (file selection, conffile handling,
`SPc.pm` rewriting). When that behavior changes, update the skill's `SKILL.md`
and `references/example.md` in the same change. Check claims against the
code, because several of them are not in the POD.
