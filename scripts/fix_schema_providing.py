#!/usr/bin/env python3
"""
Add SchemaProviding conformance to param types
"""

import re
from pathlib import Path

def fix_memory_tools():
    """Add SchemaProviding to MemorySearchParams and MemoryStoreParams"""
    file_path = Path(__file__).parent.parent / "Sources/AgentTools/MemoryTools.swift"

    with open(file_path, 'r') as f:
        content = f.read()

    # Add SchemaProviding to MemorySearchParams
    content = re.sub(
        r'public struct MemorySearchParams: Codable, Sendable \{',
        'public struct MemorySearchParams: Codable, Sendable, SchemaProviding {',
        content
    )

    # Add SchemaProviding to MemoryStoreParams
    content = re.sub(
        r'public struct MemoryStoreParams: Codable, Sendable \{',
        'public struct MemoryStoreParams: Codable, Sendable, SchemaProviding {',
        content
    )

    with open(file_path, 'w') as f:
        f.write(content)

    print(f"✅ Fixed: MemoryTools.swift")
    print("   • MemorySearchParams: SchemaProviding")
    print("   • MemoryStoreParams: SchemaProviding")

if __name__ == "__main__":
    print("🔧 Adding SchemaProviding conformance...\n")
    fix_memory_tools()
