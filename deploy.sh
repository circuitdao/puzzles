#!/bin/bash

# Circuit Puzzles Deployment Script
# This script automates version bumping, packaging, and GitHub release creation

set -e

# Global variables
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get current version from pyproject.toml
get_current_version() {
    poetry version --short
}

# Function to simulate version bump for dry-run mode
simulate_version_bump() {
    local current_version="$1"
    local version_type="$2"
    
    # Parse version into major.minor.patch
    IFS='.' read -r major minor patch <<< "$current_version"
    
    case $version_type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Function to bump version
bump_version() {
    local version_type="$1"
    
    case $version_type in
        patch|minor|major)
            if [ "$DRY_RUN" = true ]; then
                print_info "[DRY RUN] Would bump $version_type version..."
                print_info "[DRY RUN] Would run: poetry version $version_type"
            else
                print_info "Bumping $version_type version..."
                poetry version "$version_type"
            fi
            ;;
        *)
            print_error "Invalid version type: $version_type"
            print_info "Valid options: patch, minor, major"
            exit 1
            ;;
    esac
}

# Function to create GitHub release
create_github_release() {
    local version="$1"
    local tag_name="v$version"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would create GitHub release for version $version..."
        print_info "[DRY RUN] Would run: git tag $tag_name"
        print_info "[DRY RUN] Would run: git push origin $tag_name"
        
        if command_exists gh; then
            print_info "[DRY RUN] Would run: gh release create $tag_name"
        else
            print_warning "[DRY RUN] GitHub CLI (gh) not found - would need manual release creation"
        fi
        
        print_success "[DRY RUN] Skipped GitHub release creation"
    else
        print_info "Creating GitHub release for version $version..."
        
        # Create and push tag
        git tag "$tag_name"
        git push origin "$tag_name"
        
        # Create GitHub release
        if command_exists gh; then
            print_info "Using GitHub CLI to create release..."
            gh release create "$tag_name" \
                --title "Release $tag_name" \
                --notes "Automated release of circuit-puzzles version $version" \
                --draft=false \
                --prerelease=false
            
            print_success "GitHub release created: $tag_name"
        else
            print_warning "GitHub CLI (gh) not found. Please install it or create the release manually at:"
            print_warning "https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^/]*\/[^/]*\)\.git.*/\1/')/releases/new?tag=$tag_name"
        fi
    fi
}

# Function to freeze puzzle checksum
freeze_puzzle_hashes() {
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would freeze puzzle checksum..."
        print_info "[DRY RUN] Would run: python freeze_puzzle_hashes.py"
        print_success "[DRY RUN] Skipped puzzle checksum freezing"
    else
        print_info "Freezing puzzle checksum..."
        
        if [ ! -f "freeze_puzzle_hashes.py" ]; then
            print_error "freeze_puzzle_hashes.py not found"
            exit 1
        fi
        
        python freeze_puzzle_hashes.py
        
        # Verify that puzzle_checksum was added to pyproject.toml
        if ! grep -q "puzzle_checksum = " pyproject.toml; then
            print_error "Failed to add puzzle_checksum to pyproject.toml"
            exit 1
        fi
        
        print_success "Puzzle checksum frozen successfully"
    fi
}

# Function to build package
build_package() {
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would build package..."
        print_info "[DRY RUN] Would run: rm -rf dist/"
        print_info "[DRY RUN] Would run: poetry build"
        print_success "[DRY RUN] Skipped package building"
    else
        print_info "Building package..."
        
        # Clean previous builds
        rm -rf dist/
        
        # Build with Poetry
        poetry build
        
        print_success "Package built successfully"
        ls -la dist/
    fi
}

# Function to commit version changes
commit_version_changes() {
    local version="$1"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would commit version changes and puzzle checksum..."
        print_info "[DRY RUN] Would run: git add pyproject.toml"
        print_info "[DRY RUN] Would run: git commit -m \"Bump version to $version and freeze puzzle checksum\""
        print_info "[DRY RUN] Would run: git push origin main"
        print_success "[DRY RUN] Skipped git commit and push"
    else
        print_info "Committing version changes and puzzle checksum..."
        git add pyproject.toml
        git commit -m "Bump version to $version and freeze puzzle checksum"
        git push origin main
        print_success "Version changes and puzzle checksum committed and pushed"
    fi
}

# Main function
main() {
    local version_type="${1:-patch}"
    
    # Parse arguments for --dry-run flag
    for arg in "$@"; do
        if [ "$arg" = "--dry-run" ]; then
            DRY_RUN=true
            print_warning "Running in DRY RUN mode - no changes will be committed or pushed"
        fi
    done
    
    # Filter out --dry-run from arguments
    local filtered_args=()
    for arg in "$@"; do
        if [ "$arg" != "--dry-run" ]; then
            filtered_args+=("$arg")
        fi
    done
    
    # Set version_type from filtered arguments, default to "patch"
    if [ ${#filtered_args[@]} -gt 0 ]; then
        version_type="${filtered_args[0]}"
    else
        version_type="patch"
    fi
    
    print_info "Starting deployment process for circuit-puzzles..."
    
    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        print_error "Not in a Git repository"
        exit 1
    fi
    
    # Check if Poetry is installed
    if ! command_exists poetry; then
        print_error "Poetry is not installed. Please install Poetry first."
        exit 1
    fi
    
    # Check if working directory is clean (skip in dry-run mode)
    if [ "$DRY_RUN" = false ] && [ -n "$(git status --porcelain)" ]; then
        print_warning "Working directory is not clean. Please commit or stash changes first."
        git status --short
        exit 1
    fi
    
    if [ "$DRY_RUN" = true ] && [ -n "$(git status --porcelain)" ]; then
        print_warning "[DRY RUN] Working directory is not clean (this is OK in dry-run mode)"
    fi
    
    # Check if we're on the main branch (skip in dry-run mode)
    current_branch=$(git branch --show-current)
    if [ "$DRY_RUN" = false ] && [ "$current_branch" != "main" ]; then
        print_error "You must be on the 'main' branch to deploy"
        print_info "Current branch: $current_branch"
        print_info "Switch to main with: git checkout main"
        exit 1
    fi
    
    if [ "$DRY_RUN" = true ] && [ "$current_branch" != "main" ]; then
        print_warning "[DRY RUN] Not on main branch: $current_branch (this is OK in dry-run mode)"
    fi
    
    # Get current version
    current_version=$(get_current_version)
    print_info "Current version: $current_version"
    
    # Bump version
    bump_version "$version_type"
    
    if [ "$DRY_RUN" = true ]; then
        new_version=$(simulate_version_bump "$current_version" "$version_type")
        print_success "[DRY RUN] Version would be bumped from $current_version to $new_version"
    else
        new_version=$(get_current_version)
        print_success "Version bumped from $current_version to $new_version"
    fi
    
    # Freeze puzzle hashes
    freeze_puzzle_hashes
    
    # Build package
    build_package
    
    # Commit version changes
    commit_version_changes "$new_version"
    
    # Create GitHub release (this will trigger the existing GitHub Actions workflow)
    create_github_release "$new_version"
    
    if [ "$DRY_RUN" = true ]; then
        print_success "[DRY RUN] Deployment dry-run completed successfully!"
        print_info "[DRY RUN] No changes were made to the repository or published"
        print_info "To perform the actual deployment, run without --dry-run flag"
    else
        print_success "Deployment completed successfully!"
        print_info "The GitHub Actions workflow will now build and attach the package to the release."
        print_info "You can monitor the progress at: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^/]*\/[^/]*\)\.git.*/\1/')/actions"
    fi
}

# Show usage if no arguments or help requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [VERSION_TYPE] [--dry-run]"
    echo ""
    echo "VERSION_TYPE can be:"
    echo "  patch  - Bump patch version (default)"
    echo "  minor  - Bump minor version"
    echo "  major  - Bump major version"
    echo ""
    echo "Options:"
    echo "  --dry-run  - Test the deployment process without making any changes"
    echo "               (no git commits, pushes, tags, or GitHub releases)"
    echo ""
    echo "This script will:"
    echo "  1. Bump the version in pyproject.toml"
    echo "  2. Freeze puzzle checksum (update puzzle_checksum in pyproject.toml)"
    echo "  3. Build the package using Poetry"
    echo "  4. Commit and push the version changes and puzzle checksum"
    echo "  5. Create and push a Git tag"
    echo "  6. Create a GitHub release (triggers automated packaging)"
    echo ""
    echo "Examples:"
    echo "  $0                # Bump patch version"
    echo "  $0 minor          # Bump minor version"
    echo "  $0 major          # Bump major version"
    echo "  $0 --dry-run      # Test deployment without making changes"
    echo "  $0 minor --dry-run  # Test minor version bump without changes"
    exit 0
fi

# Run main function
main "$@"