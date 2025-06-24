# Guild Contract Architecture

## Overview

The Guild contract is designed to manage decentralized organizations (guilds) on Starknet. It uses a modular, component-based architecture to separate core logic, metadata, and internal utilities. The contract supports a flexible rank and permission system, allowing for fine-grained access control over guild actions.

## Storage Structure

- **guild_name**: The name of the guild (felt252).
- **owner**: The contract owner/creator (ContractAddress).
- **members**: A map from ContractAddress to Member struct, representing all guild members.
- **ranks**: A map from u8 to Rank struct, defining all possible ranks and their permissions.
- **rank_count**: The total number of ranks defined in the guild.

## Components

- **GuildComponent**: Main logic for inviting, kicking, and managing members and ranks.
- **GuildMetadataImpl**: Exposes metadata (guild name, owner, max rank) via external interface.
- **InternalImpl**: Handles initialization and internal utilities (e.g., permission checks, member/rank management).

## Member and Rank Model

- **Member**: Contains address, rank_id, and is_creator flag.
- **Rank**: Contains rank_name, can_invite, can_kick, promote, can_be_kicked.

## Permission Model

- The owner has all permissions by default.
- Each rank defines what actions a member can perform (invite, kick, promote, etc.).
- Permission checks are enforced before every sensitive action (e.g., only members with can_kick can kick others, and only if the target can_be_kicked).

## Error Handling

- All permission and existence checks use assert! with clear error messages.
- Special cases (e.g., owner/creator cannot be kicked) are handled explicitly.

## Extensibility

- The architecture supports adding new permissions, actions, or rank logic with minimal changes.
- Designed for testability and modular upgrades.
