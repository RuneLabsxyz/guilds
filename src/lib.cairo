// ========================================================================
// v0.2 Data Model
// ========================================================================

pub mod models {
    pub mod constants;
    pub mod events;
    pub mod types;
}

pub mod interfaces {
    pub mod factory;
    pub mod guild;
    pub mod ponziland;
    pub mod token;
}

pub mod factory {
    pub mod guild_factory;
}

// ========================================================================
// v0.1 Components (preserved during migration)
// ========================================================================

pub mod guild {
    pub mod guild;
    pub mod guild_contract;
}

pub mod mocks {
    pub mod guild;
    pub mod ponziland;
}

pub mod tests {
    pub mod constants;
}

pub mod erc20 {
    pub mod erc20_token;
}

pub mod token {
    pub mod guild_token;
}

pub mod governor {
    pub mod guild_governor;
}

// Keep v0.1 for backward compatibility during migration
pub mod gov {
    pub mod governance;
}
