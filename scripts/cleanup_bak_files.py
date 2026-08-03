#!/usr/bin/env python3
"""
Remove all .bak files from the project
"""

from pathlib import Path

def cleanup_bak_files(root_dir):
    """Remove all .bak files"""
    bak_files = list(Path(root_dir).rglob("*.bak"))

    for file_path in bak_files:
        try:
            file_path.unlink()
            print(f"🗑️  Deleted: {file_path.relative_to(root_dir)}")
        except Exception as e:
            print(f"❌ Error deleting {file_path}: {e}")

    print(f"\n✨ Deleted {len(bak_files)} .bak files")
    return len(bak_files)

if __name__ == "__main__":
    root = Path(__file__).parent.parent

    print("🗑️  Cleaning up .bak files...\n")
    cleanup_bak_files(root)
