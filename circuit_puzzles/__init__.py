import warnings
from pathlib import Path

from chialisp_builder import ChialispBuild
from clvm_rs import Program

try:
    from importlib.resources import files
except ImportError:
    # for py3.8
    from importlib_resources import files

PUZZLE_PATHS = [Path(x).with_suffix(".hex") for x in Path(str(files(__package__))).iterdir() if x.name.endswith(".clsp")]
clsp_builder = ChialispBuild([Path(str(files(__package__) / "include"))])
for puzzle_path in PUZZLE_PATHS:
    try:
        clsp_builder(puzzle_path)
    except Exception as e:
        print(f"Failed to compile {puzzle_path}: {e}")
        raise


def load_puzzle(puzzle_name: str) -> Program:
    from chialisp_loader import load_program

    return load_program("circuit_puzzles", f"{puzzle_name}.hex")
