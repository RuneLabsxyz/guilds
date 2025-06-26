# Guild Contract Architecture

## Overview

The Guild system is a modular set of contracts for decentralized organizations (guilds) on Starknet. Each guild is represented by:
- A **Guild contract** (membership, ranks, metadata)
- An **ERC20 equity token contract** (guild shares, minted at creation)
- A **Governance contract** (proposals, voting, execution for rank management)

**Only rank management (create, delete, change permissions) is governed by token-holder voting.**

- Inviting and kicking members remain permission-based actions, controlled by rank permissions.

## Storage Structure

- **guild_name**: The name of the guild (felt252).
- **governance**: The address of the governance contract (ContractAddress).
- **equity_token**: The address of the ERC20 equity token (ContractAddress).
- **members**: Map from ContractAddress to Member struct.
- **ranks**: Map from u8 to Rank struct.
- **rank_count**: Number of ranks.

## Components

- **GuildComponent**: Core logic for membership, ranks, and metadata. All rank management actions are gated by governance. Invite/kick are permission-based.
- **EquityToken (ERC20)**: Standard ERC20, minted 10,000 to the guild at creation. Only governance can mint/burn after initialization.
- **Governance**: Proposals, voting, execution. Can call into Guild and EquityToken contracts for rank management. Handles inactivity-based burning (future).
- **GuildMetadataImpl**: Exposes metadata.
- **InternalImpl**: Initialization and internal utilities.

## Member and Rank Model

- **Member**: Contains address, rank_id, and is_creator flag.
- **Rank**: Contains rank_name, can_invite, can_kick, promote, can_be_kicked.

## Permission Model

- The owner has all permissions by default (for legacy, but replaced by governance for rank management).
- Each rank defines what actions a member can perform (invite, kick, promote, etc.).
- Permission checks are enforced before every sensitive action (e.g., only members with can_kick can kick others, and only if the target can_be_kicked).
- **Only rank management (create, delete, change permissions) is governed.**

## Error Handling

- All permission and existence checks use assert! with clear error messages.
- Special cases (e.g., owner/creator cannot be kicked) are handled explicitly.

## High-Level Flows

- **Guild Creation**: Deploy Guild, EquityToken, and Governance contracts. Mint 10,000 tokens to the guild/creator.
- **Governance Actions**: Only rank management (add rank, change permissions, delete rank) requires a successful governance proposal and vote.
- **Inviting/Kicking**: Controlled by rank permissions, not governance.
- **Inactivity-based Burning**: (Future) Governance can propose to burn tokens from inactive wallets (no transfer for X time).

## Extensibility

- Modular contracts: ERC20, governance, and guild logic are separate and upgradeable.
- New permissions, actions, or governance models can be added with minimal changes.
- Designed for testability and upgradability.
