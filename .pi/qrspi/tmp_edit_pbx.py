import sys

# Usage: python3 tmp_edit_pbx.py '<comma,sep,line numbers>' <old> <new> <file>
lines_spec, old, new, path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
nums = [int(x) for x in lines_spec.split(",") if x.strip()] if lines_spec else []
with open(path) as f:
    data = f.readlines()
# 1-indexed -> 0-indexed
for n in sorted(nums, reverse=True):
    idx = n - 1
    assert old in data[idx], f"expected {old!r} at line {n}, got {data[idx]!r}"
    data[idx] = data[idx].replace(old, new)
with open(path, "w") as f:
    f.writelines(data)
print(f"Patched lines {lines_spec}: {old} -> {new}")