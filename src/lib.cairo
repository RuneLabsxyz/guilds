// ========================================================================
// v0.2 Data Model
// ========================================================================

pub mod models {
    pub mod types;
    pub mod events;
    pub mod constants;
}

pub mod interfaces {
    pub mod guild;
    pub mod token;
    pub mod factory;
}

// ========================================================================
// v0.1 Components (preserved during migration)
// ========================================================================

pub mod guild {
    pub mod guild_contract;
}

pub mod mocks {
    pub mod guild;
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

pub mod gov {
    pub mod governance;
}
