#!/usr/bin/env python3
"""
Remove 'import AgentCore' from all Swift files
"""

import os
import re
from pathlib import Path

def remove_agentcore_imports(root_dir):
    """Remove import AgentCore statements from all .swift files"""
    swift_files = list(Path(root_dir).rglob("*.swift"))

    fixed_count = 0
    for file_path in swift_files:
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Check if file has import AgentCore
            if 'import AgentCore' not in content:
                continue

            # Remove the import line
            new_content = re.sub(r'^import AgentCore\n', '', content, flags=re.MULTILINE)

            # Write back
            with open(file_path, 'w') as f:
                f.write(new_content)

            print(f"✅ Fixed: {file_path.relative_to(root_dir)}")
            fixed_count += 1

        except Exception as e:
            print(f"❌ Error processing {file_path}: {e}")

    print(f"\n✨ Fixed {fixed_count} files")
    return fixed_count

if __name__ == "__main__":
    root = Path(__file__).parent.parent  # SwiftAgents-Public root
    sources_dir = root / "Sources"

    print("🔍 Removing 'import AgentCore' from Swift files...\n")
    remove_agentcore_imports(sources_dir)
