"""Preserve existing VSIX artifacts; never download or rebuild installed extensions."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import uuid
import zipfile


def identity(path):
    try:
        with zipfile.ZipFile(path) as archive:
            package = json.loads(archive.read('extension/package.json').decode('utf-8-sig'))
            return (package['publisher'] + '.' + package['name']).lower(), str(package['version'])
    except (OSError, zipfile.BadZipFile, KeyError, ValueError, UnicodeError):
        return None


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=Path(__file__).resolve().parents[1] / 'manifests/extensions.json')
    parser.add_argument('--source', action='append', type=Path, required=True)
    parser.add_argument('--cache-root', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding='utf-8-sig'))
    expected = {(item['id'].lower(), str(item['version'])) for item in manifest['extensions']}
    found = {}
    for directory in args.source:
        if directory.is_dir():
            for path in directory.iterdir():
                if path.is_file() and not path.is_symlink():
                    key = identity(path)
                    if key in expected:
                        found.setdefault(key, path)
    records = []
    for key in sorted(expected):
        destination = args.cache_root / 'extensions' / (key[0] + '-' + key[1] + '.vsix')
        source = found.get(key)
        if destination.exists():
            if identity(destination) != key:
                raise RuntimeError('Existing VSIX has an unexpected identity: ' + destination.name)
            checksum = digest(destination)
            sidecar = destination.with_suffix('.vsix.sha256')
            if sidecar.exists() and sidecar.read_text(encoding='ascii').strip().lower() != checksum:
                raise RuntimeError('Existing VSIX sidecar mismatch: ' + destination.name)
            state = 'existing-identity-matched'
        elif source:
            checksum = digest(source)
            state = 'would-copy'
            if args.apply:
                destination.parent.mkdir(parents=True, exist_ok=True)
                partial = destination.with_name(destination.name + '.' + uuid.uuid4().hex + '.partial')
                shutil.copyfile(source, partial)
                if digest(partial) != checksum:
                    raise RuntimeError('Copied VSIX checksum mismatch; inspect ' + str(partial))
                # A hard link creates the final name atomically without replacing an existing file.
                os.link(partial, destination)
                partial.unlink()
                destination.with_suffix('.vsix.sha256').write_text(checksum, encoding='ascii')
                state = 'copied-identity-and-local-hash-matched'
        else:
            checksum = None
            state = 'missing'
        records.append({'id': key[0], 'version': key[1], 'state': state, 'sha256': checksum})
    report = {'apply': args.apply, 'expected': len(expected), 'missing': sum(item['state'] == 'missing' for item in records),
              'copied': sum(item['state'].startswith('copied') for item in records),
              'trust': 'Identity and locally observed content hashes; publisher authenticity is not independently established.',
              'extensions': records}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({key: value for key, value in report.items() if key != 'extensions'}))


if __name__ == '__main__':
    main()
