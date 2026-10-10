# tools/hopper_dump.py — Hopper CLI automated decompile export.
#
# Run (absolute script path is REQUIRED for -Y):
#   /usr/local/bin/hopper -e build/pe-x86_64.bin -Y "/abs/path/tools/hopper_dump.py"
#
# Output: analysis/hopper_dump.txt (single file; script force-quits Hopper via os._exit).
#
# To adapt to a new PDF Expert version: edit LABELS below.
#   - ObjC method labels:      "-[_TtC<module-len><module><class-len><class> <selector>]"
#   - Helper functions:        "sub_<addr>" — addresses SHIFT between versions,
#     re-find them via Findings in the method decompiles or Hopper GUI search.
#
# Known Hopper Python API quirks (see docs/dev-notes.md §2):
#   - no getAddressForLabel  → use getAddressForName
#   - no doc.getSegmentContaining → use doc.getSegment(0)
#   - Procedure has no getDisassembly → use decompile()
import os
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "analysis", "hopper_dump.txt"))

LABELS = [
    # --- PDF_Expert_DMG tab classes (v3.13.4) ---
    "-[_TtC14PDF_Expert_DMG14TabContentView initWithCoder:]",
    "-[_TtC14PDF_Expert_DMG14TabContentView onCloseButtonClick:]",
    # --- helper functions (addresses valid for 3.13.4 x86_64 only) ---
    "sub_1001008c0",   # TabContentView common init — the VFL constraint state machine
    "sub_100100290",   # close-button click path
    "sub_10062cdf0",   # TabView.updateConstraints implementation
]


def resolve(doc, name):
    addr = None
    detail = []
    f = getattr(doc, "getAddressForName", None)
    if f is None:
        return None, "getAddressForName absent"
    try:
        addr = f(name)
        detail.append("getAddressForName=%r" % addr)
    except Exception as e:
        detail.append("getAddressForName raised %r" % e)
    return addr, "; ".join(detail)


def render(doc, addr):
    seg = doc.getSegment(0)
    proc = seg.getProcedureAtAddress(addr) if seg else None
    chunks = ["// procedure: %r" % proc]
    if proc is not None:
        try:
            pseudo = proc.decompile()
            chunks.append("// pseudo-decompile:\n%s" % (pseudo if pseudo else "<empty>"))
        except Exception as e:
            chunks.append("// decompile raised %r" % e)
    return "\n".join(chunks)


def main():
    out = []
    try:
        doc = Document.getCurrentDocument()
        out.append("// doc=%r  segmentCount=%s" % (doc, getattr(doc, "getSegmentCount", lambda: "?")()))
        for label in LABELS:
            out.append("=" * 100)
            out.append("## %s" % label)
            try:
                addr, detail = resolve(doc, label)
                out.append("// resolve: %s" % detail)
                if addr:
                    out.append(render(doc, addr))
            except Exception:
                out.append("// EXCEPTION:\n%s" % traceback.format_exc())
    except Exception:
        out.append("// FATAL:\n%s" % traceback.format_exc())
    finally:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, "w") as f:
            f.write("\n".join(out) + "\n")
        print("[hopper_dump] wrote %s" % OUT)
        os._exit(0)


main()
