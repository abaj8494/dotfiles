#!/usr/bin/env python3
"""Extract inline base64 images from an org file, save to img/, replace with file links.

Naming convention matches ankiweb-deepmind-mle.org:
  - Derived from nearest parent heading, slugified
  - Multiple images under same heading get -2, -3, etc. suffixes
  - Truncated to ~70 chars
"""

import base64
import os
import re
import sys
import unicodedata


def slugify(text, max_len=70):
    """Convert heading text to a filename-safe slug."""
    text = text.lower().strip()
    # Remove org markup
    text = re.sub(r'\\[({[].*?[)}\]]', '', text)  # remove latex
    text = re.sub(r'[~=*/+_]', '', text)  # remove org emphasis markers
    # Normalize unicode
    text = unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode()
    # Replace non-alnum with dashes
    text = re.sub(r'[^a-z0-9]+', '-', text)
    text = text.strip('-')
    # Truncate at word boundary
    if len(text) > max_len:
        text = text[:max_len].rsplit('-', 1)[0]
    return text or 'image'


def find_current_heading(lines, line_idx):
    """Walk backwards to find the nearest org heading."""
    for i in range(line_idx, -1, -1):
        m = re.match(r'^\*+ (.+)', lines[i])
        if m:
            return m.group(1).strip()
    return 'image'


def main():
    if len(sys.argv) < 2:
        print("Usage: extract-base64-images.py <org-file>")
        sys.exit(1)

    org_file = sys.argv[1]
    org_dir = os.path.dirname(os.path.abspath(org_file))
    img_dir = os.path.join(org_dir, 'img')
    os.makedirs(img_dir, exist_ok=True)

    with open(org_file, 'r') as f:
        lines = f.readlines()

    # Pattern matches [[data:image/TYPE;base64,DATA]] with optional surrounding text
    b64_pattern = re.compile(
        r'\[\[data:image/([^;]+);base64,([A-Za-z0-9+/=]+)\]\]'
    )

    heading_counts = {}  # track how many images per heading slug
    total_extracted = 0
    total_bytes_saved = 0

    for line_idx in range(len(lines)):
        line = lines[line_idx]
        if 'data:image/' not in line or 'base64' not in line:
            continue

        new_line = line
        offset = 0  # track position shifts from replacements

        for match in list(b64_pattern.finditer(line)):
            img_type = match.group(1)  # e.g. "svg+xml" or "png"
            b64_data = match.group(2)

            # Determine extension
            if 'svg' in img_type:
                ext = 'svg'
            elif 'png' in img_type:
                ext = 'png'
            elif 'jpeg' in img_type or 'jpg' in img_type:
                ext = 'jpg'
            else:
                ext = img_type.split('+')[0]

            # Build filename from heading
            heading = find_current_heading(lines, line_idx)
            slug = slugify(heading)

            # Handle multiple images per heading
            if slug not in heading_counts:
                heading_counts[slug] = 0
            heading_counts[slug] += 1
            count = heading_counts[slug]

            if count == 1:
                filename = f"{slug}.{ext}"
            else:
                filename = f"{slug}-{count}.{ext}"

            # Decode and save
            try:
                img_bytes = base64.b64decode(b64_data)
            except Exception as e:
                print(f"  WARNING: Failed to decode base64 on line {line_idx+1}: {e}")
                continue

            filepath = os.path.join(img_dir, filename)
            with open(filepath, 'wb') as f:
                f.write(img_bytes)

            # Replace in line
            old = match.group(0)
            new = f'[[file:img/{filename}]]'
            start = match.start() + offset
            end = match.end() + offset
            new_line = new_line[:start] + new + new_line[end:]
            offset += len(new) - len(old)

            b64_len = len(b64_data)
            total_bytes_saved += b64_len
            total_extracted += 1
            print(f"  [{total_extracted}] line {line_idx+1}: {filename} ({len(img_bytes)} bytes)")

        lines[line_idx] = new_line

    # Write back
    with open(org_file, 'w') as f:
        f.writelines(lines)

    print(f"\nDone: extracted {total_extracted} images to {img_dir}/")
    print(f"Removed ~{total_bytes_saved // 1024} KB of base64 data from org file.")


if __name__ == '__main__':
    main()
