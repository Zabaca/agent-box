# npm Publishing Examples

## Example 1: Check Status

```bash
# Verify logged in
npm whoami
# Output: claude-agent

# Check registry
npm config get registry
# Output: https://registry.npmjs.org/
```

## Example 2: Standard Patch Release

```bash
cd /agent-workspace/packages/envcheck

# Run tests
npm test

# Bump version (1.5.0 → 1.5.1)
npm version patch -m "Release v%s"

# Push to GitHub
git push && git push --tags

# Publish
npm publish

# Verify
npm view envcheck version
# Output: 1.5.1
```

## Example 3: Minor Release with Changelog

```bash
cd /agent-workspace/packages/my-package

# Update CHANGELOG.md first
cat >> CHANGELOG.md << 'EOF'

## [1.1.0] - 2026-01-23

### Added
- New feature X
- Support for Y

### Fixed
- Bug in Z
EOF

# Commit changelog
git add CHANGELOG.md
git commit -m "Update changelog for v1.1.0"

# Bump minor version
npm version minor

# Push and publish
git push && git push --tags
npm publish
```

## Example 4: Pre-release Version

```bash
cd /agent-workspace/packages/my-package

# Create beta version
npm version prerelease --preid=beta
# 1.0.0 → 1.0.1-beta.0

# Publish with beta tag
npm publish --tag beta

# Users install with:
# npm install my-package@beta
```

## Example 5: First-Time Package Setup

```bash
mkdir new-package && cd new-package

# Initialize
npm init -y

# Edit package.json
cat > package.json << 'EOF'
{
  "name": "my-new-package",
  "version": "0.1.0",
  "description": "What this package does",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "files": [
    "dist",
    "README.md"
  ],
  "scripts": {
    "build": "tsc",
    "test": "vitest run",
    "prepublishOnly": "npm run build && npm test"
  },
  "keywords": ["keyword1", "keyword2"],
  "author": "claude-agent",
  "license": "MIT",
  "repository": {
    "type": "git",
    "url": "https://github.com/claude-agent-dev/my-new-package"
  }
}
EOF

# Create source
mkdir src
echo 'export const hello = () => "world";' > src/index.ts

# Build
npm run build

# Test publish (dry run)
npm publish --dry-run

# Check what will be included
npm pack --dry-run

# Publish for real
npm publish
```

## Example 6: Check Package Before Publishing

```bash
cd /agent-workspace/packages/my-package

# See what files will be published
npm pack --dry-run

# Output:
# npm notice 📦 my-package@1.0.0
# npm notice Tarball Contents
# npm notice 1.2kB dist/index.js
# npm notice 0.5kB dist/index.d.ts
# npm notice 2.1kB README.md
# npm notice 1.5kB package.json
# npm notice Tarball Details
# npm notice name: my-package
# npm notice version: 1.0.0
# npm notice total files: 4
```

## Example 7: View Package on npm

```bash
# Basic info
npm view envcheck

# Just version
npm view envcheck version

# All published versions
npm view envcheck versions

# Check download counts (use npm API)
curl -s https://api.npmjs.org/downloads/point/last-week/envcheck | jq
```

## Example 8: Deprecate Old Version

```bash
# Deprecate a version
npm deprecate my-package@1.0.0 "Security vulnerability, please upgrade to 1.0.1"

# Deprecate all versions
npm deprecate my-package "This package is no longer maintained"
```

## Example 9: Add Dist Tag

```bash
# Tag a version as stable
npm dist-tag add my-package@2.0.0 stable

# List all tags
npm dist-tag ls my-package
# Output:
# latest: 2.1.0
# stable: 2.0.0
# beta: 2.2.0-beta.1
```

## Example 10: Full Release Workflow

```bash
#!/bin/bash
# release.sh - Full release workflow

set -e

PACKAGE_DIR="/agent-workspace/packages/my-package"
cd "$PACKAGE_DIR"

echo "=== Running tests ==="
npm test

echo "=== Bumping version ==="
npm version patch -m "Release v%s"
NEW_VERSION=$(node -p "require('./package.json').version")

echo "=== Pushing to GitHub ==="
git push && git push --tags

echo "=== Publishing to npm ==="
npm publish

echo "=== Creating GitHub release ==="
gh release create "v$NEW_VERSION" --generate-notes

echo "=== Done! Published v$NEW_VERSION ==="
```

## Example 11: Login to Different Registry

```bash
# Login to npm
npm login
# Enter: claude-agent
# Enter: <password>
# Enter: agent-box@agentmail.to

# Verify
npm whoami
```

## Example 12: Package with TypeScript

```bash
# tsconfig.json for library
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "node",
    "declaration": true,
    "declarationMap": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
EOF

# Build before publish (handled by prepublishOnly)
npm publish
```

## Our Publishing Checklist

Before every publish:

- [ ] Tests pass (`npm test`)
- [ ] Version bumped appropriately
- [ ] CHANGELOG updated (if applicable)
- [ ] README is current
- [ ] TypeScript types included (if TS project)
- [ ] Dry run looks correct (`npm publish --dry-run`)
- [ ] Git is clean and pushed
