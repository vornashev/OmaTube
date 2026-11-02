# Contributing to OmaTube

Thanks for helping out. Issues and pull requests in English or Russian are both fine.

## Reporting a bug

Use the [bug report form](https://github.com/vornashev/OmaTube/issues/new?template=bug_report.yml). Include:

- the OmaTube version (`jq -r .version ~/.config/omarchy/plugins/vornashev.omatube/manifest.json`);
- what you did and what happened;
- the output of `omatube status` and the last lines of `journalctl --user -u omatube -n 50`.

If playback suddenly fails for every video, YouTube has probably changed something. Check open issues first: one may already exist.

Report security problems privately; see [SECURITY.md](SECURITY.md).

## Pull requests

1. Set up the project as described in [docs/development.md](docs/development.md).
2. Keep a pull request focused on one change.
3. Add or update tests for backend changes. Run `python -m unittest discover -s tests`, `node --test 'browser-extension/lib/*.test.mjs'` and `scripts/check.sh`.
4. Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for anything users will notice.
5. Add an English translation to `ui/i18n.js` for every new UI string.
6. For UI changes, attach a screenshot.

By contributing, you agree that your work is released under the [MIT License](LICENSE).
