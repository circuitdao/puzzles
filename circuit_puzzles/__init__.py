from clvm_rs import Program


def load_puzzle(puzzle_name: str) -> Program:
    from chialisp_loader import load_program

    return load_program("circuit_puzzles", f"{puzzle_name}.hex")
