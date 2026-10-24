"""Quote by default; explicit execution uses only the shared governed Sienna adapter."""
import argparse
import json
import os
import pathlib

import governed_deepgram as adapter


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--text-file", required=True, type=pathlib.Path)
    p.add_argument("--workspace", required=True)
    p.add_argument("--revision", required=True)
    p.add_argument("--dictionary-revision", required=True)
    p.add_argument("--expressivity", required=True, type=float)
    p.add_argument("--ledger-root", type=pathlib.Path)
    p.add_argument("--recovery-epoch-manifest", type=pathlib.Path)
    p.add_argument("--output", type=pathlib.Path)
    p.add_argument("--receipt", type=pathlib.Path)
    p.add_argument("--execute", action="store_true")
    args = p.parse_args(argv)
    text = args.text_file.read_text(encoding="utf-8")
    options = dict(workspace=args.workspace, revision=args.revision,
                   dictionary_revision=args.dictionary_revision, expressivity=args.expressivity)
    quote = adapter.quote(text, **options)
    if not args.execute:
        print(json.dumps({k: v for k, v in quote.items() if k != "request"}, indent=2))
        return 0
    if not args.output or not args.receipt or args.output.absolute() == args.receipt.absolute():
        p.error("--execute requires distinct --output and --receipt paths")
    if any(x.exists() or x.is_symlink() or not x.parent.is_dir() for x in (args.output, args.receipt)):
        p.error("Output/receipt must be absent files in existing directories")
    raw, receipt = adapter.generate(text, root=args.ledger_root,
                                   recovery_epoch_manifest=args.recovery_epoch_manifest, **options)
    # Receipt first; a later copy failure reuses ledger bytes rather than regenerating.
    for target, data in ((args.receipt, json.dumps(receipt, indent=2).encode()), (args.output, raw)):
        with target.open("xb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
    print(json.dumps(receipt, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError, OSError):
        raise SystemExit("Governed Sienna request failed; inspect shared receipt/state before retrying. No provider details logged.") from None
