use starknet::{ClassHash, ContractAddress};


//
// Contract addresses
//

pub const ADMIN: ContractAddress = 'ADMIN'.as_address();
pub const AUTHORIZED: ContractAddress = 'AUTHORIZED'.as_address();
pub const ZERO: ContractAddress = 0.as_address();
pub const CALLER: ContractAddress = 'CALLER'.as_address();
pub const OWNER: ContractAddress = 'OWNER'.as_address();
pub const NEW_OWNER: ContractAddress = 'NEW_OWNER'.as_address();
pub const OTHER: ContractAddress = 'OTHER'.as_address();
pub const OTHER_ADMIN: ContractAddress = 'OTHER_ADMIN'.as_address();
pub const SPENDER: ContractAddress = 'SPENDER'.as_address();
pub const RECIPIENT: ContractAddress = 'RECIPIENT'.as_address();
pub const OPERATOR: ContractAddress = 'OPERATOR'.as_address();
pub const DELEGATOR: ContractAddress = 'DELEGATOR'.as_address();
pub const DELEGATEE: ContractAddress = 'DELEGATEE'.as_address();
pub const TIMELOCK: ContractAddress = 'TIMELOCK'.as_address();
pub const VOTES_TOKEN: ContractAddress = 'VOTES_TOKEN'.as_address();
pub const ALICE: ContractAddress = 'ALICE'.as_address();
pub const BOB: ContractAddress = 'BOB'.as_address();
pub const CHARLIE: ContractAddress = 'CHARLIE'.as_address();

pub const CLASS_HASH_ZERO: ClassHash = 0.try_into().unwrap();

//
// Helpers
//

#[generate_trait]
pub impl AsAddressImpl of AsAddressTrait {
    /// Converts a felt252 to a ContractAddress as a constant function.
    ///
    /// Requirements:
    ///
    /// - `value` must be a valid contract address.
    const fn as_address(self: felt252) -> ContractAddress {
        self.try_into().expect('Invalid contract address')
    }
}
