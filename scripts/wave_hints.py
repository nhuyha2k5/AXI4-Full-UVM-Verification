# -*- coding: utf-8 -*-
"""Finds, in a VCD written by make_wave.ps1 -Vcd, the first moments where a channel shows each VALID/READY pattern:
  A  VALID before READY      (VALID high, READY low, then the handshake a few cycles later)
  B  READY before VALID      (READY already high, VALID rises, handshake in the first cycle of VALID)
  C  VALID and READY together (both low, then both high in the same cycle)
Usage: python scripts/wave_hints.py build/wave/<stem>.vcd [bus-scope-suffix, default 'bus'] [channel prefix ...]
Times are printed in ns as the position of the clock edge that completes the pattern."""
import re
import sys


def parse(path, scope_end, names):
    ids, scope, timescale = {}, [], 1.0
    changes = {}
    cur = 0
    with open(path, encoding="utf-8", errors="replace") as f:
        in_defs = True
        for raw in f:
            line = raw.strip()
            if in_defs:
                if line.startswith("$timescale"):
                    ts_text = line
                    while "$end" not in ts_text:
                        ts_text += " " + next(f).strip()
                    m = re.search(r"(\d+)\s*(s|ms|us|ns|ps|fs)", ts_text)
                    timescale = int(m.group(1)) * {"s": 1e9, "ms": 1e6, "us": 1e3, "ns": 1, "ps": 1e-3, "fs": 1e-6}[m.group(2)]
                if line.startswith("$scope"):
                    scope.append(line.split()[2])
                elif line.startswith("$upscope"):
                    scope.pop()
                elif line.startswith("$var"):
                    p = line.split()
                    code, ref = p[3], p[4]
                    if scope and scope[-1] == scope_end and ref in names and ref not in ids.values():
                        ids[code] = ref
                elif line.startswith("$enddefinitions"):
                    in_defs = False
                continue
            if not line:
                continue
            if line[0] == "#":
                cur = int(line[1:])
            elif line[0] in "01xzXZ" and len(line) > 1:
                code = line[1:]
                if code in ids:
                    changes.setdefault(ids[code], []).append((cur, line[0]))
            elif line[0] == "b":
                pass
    return changes, timescale


def value_before(series, t):
    v = "x"
    for tt, vv in series:
        if tt >= t:
            break
        v = vv
    return v


def main():
    path = sys.argv[1]
    scope = sys.argv[2] if len(sys.argv) > 2 else "bus"
    chans = sys.argv[3:] or ["AW", "W", "AR", "R", "B"]
    names = {"ACLK"}
    for c in chans:
        names |= {c + "VALID", c + "READY"}
    ch, ts = parse(path, scope, names)
    if "ACLK" not in ch:
        print("no ACLK in scope '%s' (is the scope name right?)" % scope)
        return
    edges = [t for t, v in ch["ACLK"] if v == "1"]
    for c in chans:
        if c + "VALID" not in ch or c + "READY" not in ch:
            print("%s: signals not found" % c)
            continue
        V, R = ch[c + "VALID"], ch[c + "READY"]
        samp = [(t, value_before(V, t) == "1", value_before(R, t) == "1") for t in edges]
        found = {}
        for i in range(2, len(samp)):
            (t0, v0, r0), (t1, v1, r1) = samp[i - 1], samp[i]
            tm1, vm1, rm1 = samp[i - 2]
            if v1 and r1 and "A" not in found and v0 and not r0:
                found["A"] = (t1, "VALID lên trước, READY lên sau")
            if v1 and r1 and "B" not in found and (not v0) and r0:
                found["B"] = (t1, "READY đã ở mức cao, VALID lên và bắt tay ngay chu kỳ đầu")
            if v1 and r1 and "C" not in found and (not v0) and (not r0):
                found["C"] = (t1, "VALID và READY cùng lên trong một chu kỳ")
        print("kênh %s:" % c)
        for k in "ABC":
            if k in found:
                t, d = found[k]
                ns = t * ts
                print("   trường hợp %s  bắt tay hoàn tất ở cạnh clock t = %.1f ns   (%s)   -> zoom %.0f ns .. %.0f ns" % (k, ns, d, ns - 50, ns + 30))
            else:
                print("   trường hợp %s  không có trong file này" % k)


main()
