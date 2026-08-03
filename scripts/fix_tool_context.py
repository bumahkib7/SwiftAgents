#!/usr/bin/env python3
"""
Add ToolContext conformance to MemoryToolsContext
"""

import re
from pathlib import Path

def fix_context():
    """Add ToolContext to MemoryToolsContext"""
    file_path = Path(__file__).parent.parent / "Sources/AgentTools/MemoryTools.swift"

    with open(file_path, 'r') as f:
        content = f.read()

    # Replace MemoryToolsContext definition
    content = re.sub(
        r'public struct MemoryToolsContext: Sendable \{',
        'public struct MemoryToolsContext: ToolContext {',
        content
    )

    with open(file_path, 'w') as f:
        f.write(content)

    print(f"✅ Fixed: MemoryToolsContext now conforms to ToolContext")

if __name__ == "__main__":
    fix_context()
