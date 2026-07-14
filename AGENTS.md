# Project

Factorio MOD.

# Development

## Build and Install

- `mise run install` - Install to local Factorio MOD directory. Uses `git archive` internally, so only committed files are included — commit changes before running.

## Release

Releases are handled by GitHub Actions workflows. Do not run `mise run release:*` manually.

Changelog is managed by `factorix mod changelog` and follows Factorio's changelog.txt specification.

### What to write in changelog.txt

- Regular releases: limit entries to user-visible changes only.
- Initial release: write "Initial release" only.

### Updating the changelog during development

Write entries in the Unreleased section at the top of the file. If no Unreleased section exists, create one.

Do not create a section for the next release version directly — version bumping is handled by the GitHub Actions release workflow.

# Document Map

- README.md: Project overview

# External References

- [Factorio API](https://lua-api.factorio.com/latest/)
- [Factorio Wiki](https://wiki.factorio.com/)
