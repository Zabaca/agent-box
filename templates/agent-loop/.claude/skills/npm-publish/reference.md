# npm CLI Reference

## Authentication

| Command | Description |
|---------|-------------|
| `npm login` | Log in to registry |
| `npm logout` | Log out |
| `npm whoami` | Show current user |
| `npm token list` | List access tokens |
| `npm token create` | Create new token |
| `npm token revoke <id>` | Revoke token |

## Publishing

| Command | Description |
|---------|-------------|
| `npm publish` | Publish package |
| `npm publish --access public` | Publish scoped package publicly |
| `npm publish --tag beta` | Publish with dist-tag |
| `npm publish --dry-run` | Preview without publishing |
| `npm publish --otp 123456` | Publish with 2FA code |

## Versioning

| Command | Result |
|---------|--------|
| `npm version patch` | 1.0.0 → 1.0.1 |
| `npm version minor` | 1.0.0 → 1.1.0 |
| `npm version major` | 1.0.0 → 2.0.0 |
| `npm version prepatch` | 1.0.0 → 1.0.1-0 |
| `npm version preminor` | 1.0.0 → 1.1.0-0 |
| `npm version premajor` | 1.0.0 → 2.0.0-0 |
| `npm version prerelease` | 1.0.0-0 → 1.0.0-1 |
| `npm version 2.0.0` | Set exact version |

### Version Flags

```bash
npm version patch -m "Release %s"      # Custom commit message
npm version patch --no-git-tag-version # Don't create git tag
npm version patch --preid beta         # 1.0.1-beta.0
```

## Package Info

```bash
npm view <package>                # Full package info
npm view <package> version        # Current version
npm view <package> versions       # All versions
npm view <package> dist-tags      # Tagged versions
npm view <package> dependencies   # Dependencies
npm view <package> repository.url # Repo URL
```

## Dist Tags

```bash
npm dist-tag ls <package>              # List tags
npm dist-tag add <package>@<ver> <tag> # Add tag
npm dist-tag rm <package> <tag>        # Remove tag
```

Common tags:
- `latest` - Default for `npm install`
- `beta` - Pre-release versions
- `next` - Upcoming release
- `canary` - Bleeding edge

## Unpublish/Deprecate

```bash
npm unpublish <package>@<version>  # Remove specific version
npm unpublish <package> --force    # Remove entire package (72h limit)
npm deprecate <package> "message"  # Mark as deprecated
```

## Registry

```bash
npm config get registry            # Show current registry
npm config set registry <url>      # Set registry
npm search <term>                  # Search packages
npm pack                           # Create tarball
npm pack --dry-run                 # Show what would be packed
```

## package.json Fields

### Required for Publishing

```json
{
  "name": "package-name",
  "version": "1.0.0"
}
```

### Recommended

```json
{
  "name": "package-name",
  "version": "1.0.0",
  "description": "Package description",
  "main": "dist/index.js",
  "module": "dist/index.mjs",
  "types": "dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.mjs",
      "require": "./dist/index.js",
      "types": "./dist/index.d.ts"
    }
  },
  "files": ["dist"],
  "scripts": {
    "build": "tsup",
    "test": "vitest run",
    "prepublishOnly": "npm run build && npm test"
  },
  "keywords": ["keyword1", "keyword2"],
  "author": "Your Name <email@example.com>",
  "license": "MIT",
  "repository": {
    "type": "git",
    "url": "https://github.com/user/repo"
  },
  "bugs": {
    "url": "https://github.com/user/repo/issues"
  },
  "homepage": "https://github.com/user/repo#readme",
  "engines": {
    "node": ">=18"
  }
}
```

### files vs .npmignore

**files (whitelist):**
```json
{
  "files": ["dist", "README.md"]
}
```

**.npmignore (blacklist):**
```
src/
tests/
*.test.js
.github/
```

Always included regardless:
- package.json
- README
- LICENSE/LICENCE
- CHANGELOG

Always excluded:
- .git
- node_modules
- .npmrc

## Lifecycle Scripts

```json
{
  "scripts": {
    "prepublishOnly": "npm run build && npm test",
    "prepare": "npm run build",
    "preversion": "npm test",
    "version": "npm run build && git add -A",
    "postversion": "git push && git push --tags"
  }
}
```

| Hook | When |
|------|------|
| prepublishOnly | Before `npm publish` |
| prepare | After `npm install`, before `npm publish` |
| preversion | Before `npm version` |
| version | After version change, before commit |
| postversion | After version commit |

## 2FA Settings

```bash
# Require 2FA for publishing
npm profile enable-2fa auth-and-writes

# Require 2FA only for login
npm profile enable-2fa auth-only

# Disable 2FA
npm profile disable-2fa
```

## Scoped Packages

```bash
# Create scoped package
npm init --scope=@myorg

# Publish scoped (must specify access first time)
npm publish --access public

# Or set default
npm config set access public
```

## Troubleshooting Commands

```bash
# Check what will be published
npm pack --dry-run

# Verify package.json
npm pkg get

# Check for issues
npm audit

# Clear cache
npm cache clean --force
```
