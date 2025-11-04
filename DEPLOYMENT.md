# Circuit Puzzles Deployment Guide

This document explains how to deploy new releases of the circuit-puzzles package using the automated deployment script.

## Overview

The deployment process is automated using the `deploy.sh` script, which handles:
- Version bumping in `pyproject.toml`
- Puzzle checksum freezing for integrity verification
- Package building with Poetry
- Git tagging and commits
- GitHub release creation
- Integration with existing GitHub Actions workflow

## Prerequisites

1. **Poetry**: Ensure Poetry is installed and working
   ```bash
   poetry --version
   ```

2. **Git**: Ensure you have write access to the repository and are on the main branch

3. **GitHub CLI (optional but recommended)**: Install `gh` CLI for automatic release creation
   ```bash
   # macOS
   brew install gh
   
   # Linux/Windows
   # See: https://cli.github.com/manual/installation
   ```

4. **Clean working directory**: Ensure all changes are committed before running the script

## Usage

### Basic Usage

```bash
# Bump patch version (1.0.0 -> 1.0.1)
./deploy.sh

# Bump minor version (1.0.0 -> 1.1.0)
./deploy.sh minor

# Bump major version (1.0.0 -> 2.0.0)
./deploy.sh major
```

### Help

```bash
./deploy.sh --help
```

## Deployment Process

When you run the script, it will:

1. **Validate environment**:
   - Check if you're in a Git repository
   - Verify Poetry is installed
   - Ensure working directory is clean

2. **Version management**:
   - Display current version
   - Bump version according to specified type (patch/minor/major)
   - Update `pyproject.toml` with new version

3. **Puzzle checksum freezing**:
   - Run `freeze_puzzle_hashes.py` to generate a single SHA256 checksum for all compiled puzzles
   - Update `puzzle_checksum` field in `pyproject.toml` with the checksum
   - Ensures puzzle integrity verification for the release (see `PUZZLE_INTEGRITY.md`)

4. **Package building**:
   - Clean previous builds (`dist/` directory)
   - Build new package with Poetry
   - Display built artifacts

5. **Git operations**:
   - Commit version changes and puzzle checksum to Git
   - Push changes to main branch
   - Create and push version tag (e.g., `v1.0.1`)

6. **GitHub release**:
   - Create GitHub release with the new tag
   - Trigger existing GitHub Actions workflow
   - Workflow will build and attach package files to release

## Puzzle Integrity Verification

Starting from version 1.3.0, the package includes a checksum-based integrity verification system to ensure compiled puzzles haven't been corrupted or tampered with during distribution.

**How it works:**
- During deployment, `freeze_puzzle_hashes.py` generates a single SHA256 checksum for all `.hex` files
- This checksum is stored in the `puzzle_checksum` field in `pyproject.toml`
- When users import the package, the checksum is verified automatically
- If any mismatch is detected, a `PuzzleIntegrityError` is raised

**For more details**, see [`PUZZLE_INTEGRITY.md`](PUZZLE_INTEGRITY.md) which covers:
- How the verification system works
- Security considerations
- Troubleshooting checksum mismatches
- Manual checksum generation

## Integration with GitHub Actions

The script works with the existing `.github/workflows/build-and-release.yaml` workflow:

- The script creates a GitHub release
- This triggers the workflow automatically
- The workflow builds the package and attaches wheel files to the release
- Uses `MY_PERSONAL_ACCESS_TOKEN` for authentication

## Version Numbering

The project follows semantic versioning (SemVer):
- **Patch** (1.0.0 -> 1.0.1): Bug fixes and small changes
- **Minor** (1.0.0 -> 1.1.0): New features, backward compatible
- **Major** (1.0.0 -> 2.0.0): Breaking changes

## Troubleshooting

### Working directory not clean
If you see this error, commit or stash your changes first:
```bash
git status
git add .
git commit -m "Your commit message"
```

### GitHub CLI not found
If you don't have `gh` CLI installed:
- The script will provide a manual link to create the release
- You can still create the release manually, which will trigger the workflow

### Poetry not found
Install Poetry:
```bash
curl -sSL https://install.python-poetry.org | python3 -
```

### Permission denied
Make the script executable:
```bash
chmod +x deploy.sh
```

## Manual Process (if script fails)

If the automated script fails, you can perform the steps manually:

1. Update version in `pyproject.toml`
2. Freeze puzzle checksum: `python freeze_puzzle_hashes.py`
3. Commit changes: `git commit -am "Bump version to X.Y.Z and freeze puzzle checksum"`
4. Push changes: `git push origin main`
5. Create tag: `git tag vX.Y.Z`
6. Push tag: `git push origin vX.Y.Z`
7. Create GitHub release at: https://github.com/your-org/puzzles/releases/new

## Monitoring

After deployment:
- Monitor GitHub Actions at: https://github.com/your-org/puzzles/actions
- Check release page for attached package files
- Verify package can be installed: `pip install circuit-puzzles==X.Y.Z`

## Current Setup

- **Current version**: 1.0.0 (as of script creation)
- **Package name**: circuit-puzzles
- **Python package**: circuit_puzzles
- **Main branch**: main
- **Tag format**: v{version} (e.g., v1.0.1)