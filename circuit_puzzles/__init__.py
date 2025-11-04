"""Circuit Puzzles - Compiled Chialisp puzzles for Circuit Protocol.

This module automatically compiles and loads Chialisp puzzle files with
integrity verification to protect against corruption or tampering.

Checksum Verification:
    On import, all compiled .hex puzzle files are verified against a single SHA256
    checksum stored in pyproject.toml. If a mismatch is detected, a PuzzleIntegrityError
    is raised to prevent use of potentially corrupted or tampered puzzles.

Release Process:
    Before each release, run freeze_puzzle_hashes.py to generate a checksum
    for all puzzles and update pyproject.toml. See PUZZLE_INTEGRITY.md for details.

Example:
    >>> import circuit_puzzles
    >>> # Checksum verification happens automatically on import
    >>> puzzle = circuit_puzzles.load_puzzle('governance')
"""
from pathlib import Path
import re
import hashlib

from chia_rs import Program
from chialisp import compile_clvm, compile

PUZZLES = {}


class PuzzleIntegrityError(Exception):
    """Raised when puzzle checksum verification fails."""
    pass


def compute_puzzles_checksum(package_path: Path) -> str:
    """Compute a single SHA256 checksum for all puzzle .hex files.
    
    Args:
        package_path: Path to the package directory
        
    Returns:
        Hexadecimal SHA256 checksum string
    """
    hasher = hashlib.sha256()
    
    # Process all .hex files in sorted order for deterministic results
    hex_files = sorted(package_path.glob("*.hex"))
    
    for hex_file in hex_files:
        content = hex_file.read_text().strip()
        hasher.update(content.encode())
    
    return hasher.hexdigest()


def read_checksum_from_pyproject(package_path: Path) -> str | None:
    """Read the puzzle_checksum from pyproject.toml.
    
    Args:
        package_path: Path to the package directory
        
    Returns:
        Checksum string if found, None otherwise
    """
    # pyproject.toml is in the parent directory of the package
    pyproject_path = package_path.parent / "pyproject.toml"
    
    if not pyproject_path.exists():
        return None
    
    content = pyproject_path.read_text()
    match = re.search(r'puzzle_checksum = "([a-f0-9]{64})"', content)
    
    if match:
        return match.group(1)
    
    return None


def verify_puzzle_checksum(package_path: Path, expected_checksum: str) -> None:
    """Verify that all puzzles match the expected checksum.
    
    Args:
        package_path: Path to the package directory
        expected_checksum: Expected SHA256 checksum
        
    Raises:
        PuzzleIntegrityError: If checksum mismatch is detected
    """
    actual_checksum = compute_puzzles_checksum(package_path)
    
    if actual_checksum != expected_checksum:
        raise PuzzleIntegrityError(
            f"Puzzle checksum mismatch: expected {expected_checksum}, got {actual_checksum}. "
            f"The puzzle files may be corrupted or tampered with."
        )


def compile_module_with_symbols(include_paths, source):
    path_obj = Path(source)
    file_path = path_obj.parent
    file_stem = path_obj.stem
    # match if source file modified time is newer than target file, in which case we compile, otherwise skip
    target_file = file_path / (file_stem + ".hex")
    if target_file.exists() and target_file.stat().st_mtime > path_obj.stat().st_mtime:
        return
    target_file = file_path / (file_stem + ".hex")
    compile_clvm(source, str(target_file.absolute()), include_paths)

try:
    from importlib.resources import files
except ImportError:
    # for py3.8
    from importlib_resources import files
PUZZLE_PATHS = [str(Path(x)) for x in Path(str(files(__package__))).rglob("*.clsp")]

for puzzle_path in PUZZLE_PATHS:
    try:
        compile_module_with_symbols([str(files(__package__) / "include")], puzzle_path)
    except Exception as e:
        print(f"Failed to compile {puzzle_path}: {e}")
        raise

# Verify puzzle integrity after compilation
package_dir = Path(str(files(__package__)))
expected_checksum = read_checksum_from_pyproject(package_dir)

if expected_checksum:
    try:
        verify_puzzle_checksum(package_dir, expected_checksum)
        # Count puzzles for informational message
        puzzle_count = len(list(package_dir.glob("*.hex")))
        print(f"✓ Puzzle integrity verified: {puzzle_count} puzzles checked (checksum: {expected_checksum[:16]}...)")
    except PuzzleIntegrityError as e:
        print("ERROR: Puzzle integrity check failed!")
        print(f"  {e}")
        raise
    except Exception as e:
        print(f"WARNING: Failed to verify puzzle checksum: {e}")
        # Don't fail on unexpected errors during verification
else:
    print("WARNING: No puzzle_checksum found in pyproject.toml. Puzzle integrity verification skipped.")
    print("  To enable verification, run freeze_puzzle_hashes.py to generate the checksum.")

    
def load_puzzle(puzzle_name: str) -> Program:
    if puzzle_name in PUZZLES:
        return PUZZLES[puzzle_name]
    puzzle_data = files(__package__).joinpath(f"{puzzle_name}.hex").read_text()
    try:
        puzzle_program = Program.fromhex(puzzle_data.strip())
        PUZZLES[puzzle_name] = puzzle_program
        return puzzle_program
    except ValueError:
        print(f"Failed to load puzzle {puzzle_name}: Invalid hex data: {puzzle_data}")
