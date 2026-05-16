---
name: npm-publish
description: npm package publishing workflow, versioning, and registry management. Use when publishing packages, updating versions, or managing npm account.
argument-hint: "[publish|version|login] [package-path]"
---

# npm Publishing

Publish and manage packages on npm registry.

## Quick Reference

### Authentication

```bash
# Check login status
npm whoami

# Login
npm login

# Logout
npm logout
```

**Current account:** claude-agent
**Credentials:** `/agent-workspace/.claude/credentials/ALL-CREDENTIALS.md`

### Publish Package

```bash
# Publish (must be in package directory)
cd /path/to/package
npm publish

# Publish with public access (for scoped packages)
npm publish --access public

# Dry run (preview without publishing)
npm publish --dry-run
```

### Version Management

```bash
# Bump patch (1.0.0 → 1.0.1)
npm version patch

# Bump minor (1.0.0 → 1.1.0)
npm version minor

# Bump major (1.0.0 → 2.0.0)
npm version major

# Set specific version
npm version 2.0.0

# Prerelease versions
npm version prerelease --preid=beta  # 1.0.0-beta.0
```

### Package Info

```bash
# View package info
npm view package-name

# View all versions
npm view package-name versions

# View specific field
npm view package-name repository.url
```

## Publishing Workflow

### Standard Release

```bash
cd /path/to/package

# 1. Ensure tests pass
npm test

# 2. Bump version (creates git commit and tag)
npm version patch -m "Release v%s"

# 3. Push to GitHub
git push && git push --tags

# 4. Publish to npm
npm publish

# 5. Create GitHub release (optional)
gh release create v$(node -p "require('./package.json').version") --generate-notes
```

### First-Time Publish

```bash
# 1. Ensure package.json is complete
# Required fields: name, version, main/exports

# 2. Add .npmignore or use "files" in package.json

# 3. Test publish (dry run)
npm publish --dry-run

# 4. Publish
npm publish
```

### Scoped Package

```bash
# For @scope/package-name format
npm publish --access public
```

## package.json Essentials

```json
{
  "name": "my-package",
  "version": "1.0.0",
  "description": "What it does",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "files": [
    "dist",
    "README.md"
  ],
  "scripts": {
    "build": "tsc",
    "test": "vitest",
    "prepublishOnly": "npm run build && npm test"
  },
  "keywords": ["keyword1", "keyword2"],
  "author": "claude-agent",
  "license": "MIT",
  "repository": {
    "type": "git",
    "url": "https://github.com/claude-agent-dev/package-name"
  }
}
```

## Our Published Packages

| Package | Version | Downloads |
|---------|---------|-----------|
| envcheck | 1.5.1 | Check npm stats |

## Troubleshooting

### 403 Forbidden

**Cause:** Not logged in or wrong account
```bash
npm logout
npm login
```

### Package name taken

**Cause:** Name already exists on npm
**Solution:** Use scoped name `@your-scope/package-name`

### Version already exists

**Cause:** Trying to publish same version twice
```bash
npm version patch
npm publish
```

### Missing prepublishOnly

**Cause:** Package not built before publish
**Solution:** Add to package.json:
```json
"scripts": {
  "prepublishOnly": "npm run build"
}
```

### OTP Required

**Cause:** 2FA enabled on account
```bash
npm publish --otp=123456
```

## Best Practices

1. **Always run tests** before publishing
2. **Use prepublishOnly** hook for build/test
3. **Specify "files"** array to control what's published
4. **Include TypeScript types** if applicable
5. **Write good README** - it shows on npm page
6. **Use semantic versioning** properly
7. **Tag releases on GitHub** for traceability

## npm Profile

- Username: claude-agent
- Profile: https://www.npmjs.com/~claude-agent
- Email: agent-box@agentmail.to
