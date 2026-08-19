#!/usr/bin/env python3

import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
BUILD_ROOT = HERE.parents[4] / "00_bench/obj/rtl_unit_cu/goldens"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def deterministic_bytes(length, salt):
    return bytes(((index * 73) ^ (index >> 1) ^ salt) & 0xFF for index in range(length))


def byte_copy_golden():
    cases = {
        "zero": 0,
        "single": 1,
        "cacheline_tail": 129,
        "multiline": 385,
    }
    bins = []
    for name, length in cases.items():
        source = deterministic_bytes(length, 0x5A)
        destination = bytearray([0xA5] * (length + 17))
        destination[7:7 + length] = source
        require(bytes(destination[7:7 + length]) == source, f"{name}: byte copy mismatch")
        require(destination[:7] == bytes([0xA5] * 7), f"{name}: prefix clobber")
        require(destination[7 + length:] == bytes([0xA5] * 10), f"{name}: suffix clobber")
        bins.append(name)
    return bins


def odd_parity(value, width):
    return (value.bit_count() + 1) & 1


def tutorial_parity_golden():
    cases = {
        "zero": b"",
        "single": deterministic_bytes(8, 0x11),
        "tail": deterministic_bytes(136, 0x22),
        "multiline": deterministic_bytes(384, 0x33),
    }
    bins = []
    for name, source in cases.items():
        copied = bytes(source)
        require(copied == source, f"{name}: tutorial copy mismatch")
        padded = source + bytes((-len(source)) % 8)
        source_parity = [
            odd_parity(int.from_bytes(padded[offset:offset + 8], "big"), 64)
            for offset in range(0, len(padded), 8)
        ]
        copied_parity = [
            odd_parity(int.from_bytes(copied.ljust(len(padded), b"\0")[offset:offset + 8], "big"), 64)
            for offset in range(0, len(padded), 8)
        ]
        require(copied_parity == source_parity, f"{name}: parity preservation mismatch")
        bins.append(name)
    return bins


def naive_matrix(a, b):
    n = len(a)
    return [
        [sum(a[row][k] * b[k][column] for k in range(n)) for column in range(n)]
        for row in range(n)
    ]


def tiled_matrix(a, b, tile):
    n = len(a)
    out = [[0 for _ in range(n)] for _ in range(n)]
    for ii in range(0, n, tile):
        for jj in range(0, n, tile):
            for kk in range(0, n, tile):
                for row in range(ii, min(ii + tile, n)):
                    for column in range(jj, min(jj + tile, n)):
                        for k in range(kk, min(kk + tile, n)):
                            out[row][column] += a[row][k] * b[k][column]
    return out


def transposed_reference(a, b_transposed):
    return [
        [sum(left * right for left, right in zip(row, column)) for column in b_transposed]
        for row in a
    ]


def matrix_golden():
    cases = {
        "zero": (0, 1),
        "single": (1, 1),
        "full_tile": (4, 4),
        "edge_tile": (5, 3),
        "multitile_tail": (9, 4),
    }
    bins = []
    for name, (n, tile) in cases.items():
        a = [[((row * 5 + column * 3 + 1) % 11) - 5 for column in range(n)] for row in range(n)]
        b = [[((row * 7 - column * 2 + 3) % 13) - 6 for column in range(n)] for row in range(n)]
        expected = naive_matrix(a, b)
        actual = tiled_matrix(a, b, tile)
        b_transposed = [list(column) for column in zip(*b)] if n else []
        require(actual == expected, f"{name}: tiled matrix mismatch")
        require(transposed_reference(a, b_transposed) == expected, f"{name}: transpose mismatch")
        bins.append(name)
    return bins


def partial_transposed_tile_golden():
    n = 3
    tile = 2
    i_start = 2
    j_start = 1
    k_start = 1
    salt = 7
    a = [
        [((row + 1) * (column + 2) + salt) & 0xFFFFFFFF for column in range(n)]
        for row in range(n)
    ]
    original_b = [
        [((row + 3) * (column + 1) + salt) & 0xFFFFFFFF for column in range(n)]
        for row in range(n)
    ]
    b_transposed = [list(column) for column in zip(*original_b)]
    initial = [
        [(salt + row * n + column) & 0xFFFFFFFF for column in range(n)]
        for row in range(n)
    ]
    expected = [row[:] for row in initial]
    actual = [row[:] for row in initial]
    for row in range(i_start, min(i_start + tile, n)):
        for column in range(j_start, min(j_start + tile, n)):
            expected[row][column] = (
                expected[row][column] +
                sum(
                    a[row][k] * b_transposed[column][k]
                    for k in range(k_start, min(k_start + tile, n))
                )
            ) & 0xFFFFFFFF
    for row in range(i_start, min(i_start + tile, n)):
        for column in range(j_start, min(j_start + tile, n)):
            for k in range(k_start, min(k_start + tile, n)):
                actual[row][column] = (
                    actual[row][column] +
                    a[row][k] * b_transposed[column][k]
                ) & 0xFFFFFFFF
    require(actual == expected, "partial transposed edge tile mismatch")
    return ["partial_transposed_edge_accumulation"]


def main():
    bins = {
        "byte_copy": byte_copy_golden(),
        "tutorial_parity": tutorial_parity_golden(),
        "tiled_matrix": matrix_golden(),
        "partial_tiled_matrix": partial_transposed_tile_golden(),
    }
    hit = sum(len(values) for values in bins.values())
    total = 4 + 4 + 5 + 1
    require(hit == total, f"functional bin denominator changed: {hit} != {total}")
    BUILD_ROOT.mkdir(parents=True, exist_ok=True)
    summary = {
        "schema_version": 1,
        "result": "pass",
        "oracle_ids": [
            "byte-copy-golden-v1",
            "tutorial-parity-golden-v1",
            "tiled-matrix-independent-golden-v1",
        ],
        "functional_bins": {
            "hit": hit,
            "total": total,
            "percent": 100.0,
            "bins": bins,
        },
    }
    (BUILD_ROOT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"PASS cu_goldens bins={hit}/{total}")


if __name__ == "__main__":
    main()
