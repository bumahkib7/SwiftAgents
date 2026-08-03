#!/usr/bin/env python3
"""
Study AgentRunKit API by reading its source code from .build
"""

import os
import re
from pathlib import Path

def find_agentrunkit_sources():
    """Find AgentRunKit source files in .build directory"""
    build_dir = Path.home() / "IdeaProjects/SwiftAgents-Public/.build/checkouts"

    # Find AgentRunKit checkout
    agentrunkit_dirs = list(build_dir.glob("AgentRunKit*"))
    if not agentrunkit_dirs:
        print("❌ AgentRunKit not found in .build/checkouts")
        return None

    return agentrunkit_dirs[0] / "Sources"

def extract_public_types(source_dir):
    """Extract public types, protocols, and classes from Swift files"""
    if not source_dir or not source_dir.exists():
        return {}

    types = {
        "protocols": [],
        "structs": [],
        "classes": [],
        "enums": [],
        "functions": []
    }

    swift_files = list(source_dir.rglob("*.swift"))

    for file_path in swift_files:
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Find public protocols
            protocols = re.findall(r'public protocol (\w+)', content)
            types["protocols"].extend([(p, file_path.name) for p in protocols])

            # Find public structs
            structs = re.findall(r'public struct (\w+)', content)
            types["structs"].extend([(s, file_path.name) for s in structs])

            # Find public classes
            classes = re.findall(r'public (?:final )?class (\w+)', content)
            types["classes"].extend([(c, file_path.name) for c in classes])

            # Find public enums
            enums = re.findall(r'public enum (\w+)', content)
            types["enums"].extend([(e, file_path.name) for e in enums])

        except Exception as e:
            pass

    return types

def print_api_summary(types):
    """Print a summary of AgentRunKit's public API"""
    print("\n📚 AgentRunKit Public API Summary\n")
    print("=" * 60)

    print("\n🔧 Protocols:")
    for name, file in sorted(set(types["protocols"])):
        print(f"  • {name:30} ({file})")

    print("\n📦 Structs:")
    for name, file in sorted(set(types["structs"]))[:20]:  # Limit to 20
        print(f"  • {name:30} ({file})")

    print("\n🏛️  Classes:")
    for name, file in sorted(set(types["classes"])):
        print(f"  • {name:30} ({file})")

    print("\n📋 Enums:")
    for name, file in sorted(set(types["enums"]))[:15]:  # Limit to 15
        print(f"  • {name:30} ({file})")

    print("\n" + "=" * 60)

def find_agent_and_tool_types(source_dir):
    """Find the main Agent and Tool types"""
    if not source_dir or not source_dir.exists():
        return

    print("\n🔍 Looking for Agent and Tool implementations...\n")

    # Look for Agent definition
    agent_files = list(source_dir.rglob("*Agent*.swift"))
    for file_path in agent_files:
        with open(file_path, 'r') as f:
            content = f.read()

        # Find Agent struct/class definition
        agent_def = re.search(r'public (?:struct|class) Agent[<\w\s,>]*\{', content)
        if agent_def:
            print(f"✅ Found Agent in: {file_path.name}")
            # Extract first 10 lines after definition
            lines = content[agent_def.start():].split('\n')[:15]
            print("```swift")
            print('\n'.join(lines))
            print("```\n")

    # Look for Tool definition
    tool_files = list(source_dir.rglob("*Tool*.swift"))
    for file_path in tool_files:
        with open(file_path, 'r') as f:
            content = f.read()

        # Find Tool struct definition
        tool_def = re.search(r'public struct Tool[<\w\s,>]*\{', content)
        if tool_def:
            print(f"✅ Found Tool in: {file_path.name}")
            # Extract first 10 lines after definition
            lines = content[tool_def.start():].split('\n')[:15]
            print("```swift")
            print('\n'.join(lines))
            print("```\n")

if __name__ == "__main__":
    print("🔍 Studying AgentRunKit API...")

    source_dir = find_agentrunkit_sources()

    if source_dir:
        print(f"✅ Found AgentRunKit sources: {source_dir}")

        types = extract_public_types(source_dir)
        print_api_summary(types)

        find_agent_and_tool_types(source_dir)
    else:
        print("\n💡 Run 'swift package resolve' first to download AgentRunKit")
