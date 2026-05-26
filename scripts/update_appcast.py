#!/usr/bin/env python3
"""Prepend a new release item to docs/appcast.xml."""
import argparse
from datetime import datetime, timezone

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--version', required=True)
    p.add_argument('--build',   required=True)
    p.add_argument('--sig',     required=True)
    p.add_argument('--length',  required=True)
    p.add_argument('--repo',    required=True)
    args = p.parse_args()

    date = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')
    url  = f'https://github.com/{args.repo}/releases/download/v{args.version}/tully.zip'

    new_item = (
        f'        <item>\n'
        f'            <title>Version {args.version}</title>\n'
        f'            <pubDate>{date}</pubDate>\n'
        f'            <sparkle:version>{args.build}</sparkle:version>\n'
        f'            <sparkle:shortVersionString>{args.version}</sparkle:shortVersionString>\n'
        f'            <enclosure\n'
        f'                url="{url}"\n'
        f'                sparkle:edSignature="{args.sig}"\n'
        f'                length="{args.length}"\n'
        f'                type="application/octet-stream" />\n'
        f'        </item>\n'
    )

    with open('docs/appcast.xml', 'r') as f:
        content = f.read()

    marker = '        <item>'
    if marker in content:
        content = content.replace(marker, new_item + marker, 1)
    else:
        content = content.replace('    </channel>', new_item + '    </channel>', 1)

    with open('docs/appcast.xml', 'w') as f:
        f.write(content)

    print(f'appcast updated: v{args.version} (build {args.build})')

if __name__ == '__main__':
    main()
