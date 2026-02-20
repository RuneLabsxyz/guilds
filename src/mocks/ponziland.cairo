#[starknet::contract]
pub mod PonziLandMock {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        last_buy_location: u16,
        last_buy_price: u256,
        last_buy_stake_amount: u256,
        last_buy_token_for_sale: ContractAddress,
        last_sell_location: u16,
        last_claim_location: u16,
        last_set_price_location: u16,
        last_set_price_value: u256,
        last_stake_location: u16,
        last_stake_amount: u256,
        last_withdraw_location: u16,
        call_count: u32,
    }

    #[abi(per_item)]
    #[generate_trait]
    impl PonziLandImpl of IPonziLandMock {
        #[external(v0)]
        fn buy(
            ref self: ContractState,
            land_location: u16,
            token_for_sale: ContractAddress,
            sell_price: u256,
            amount_to_stake: u256,
        ) {
            self.last_buy_location.write(land_location);
            self.last_buy_price.write(sell_price);
            self.last_buy_stake_amount.write(amount_to_stake);
            self.last_buy_token_for_sale.write(token_for_sale);
            self.call_count.write(self.call_count.read() + 1);
        }

        #[external(v0)]
        fn sell(ref self: ContractState, land_location: u16) {
            self.last_sell_location.write(land_location);
            self.call_count.write(self.call_count.read() + 1);
        }

        #[external(v0)]
        fn increase_price(ref self: ContractState, land_location: u16, new_price: u256) {
            self.last_set_price_location.write(land_location);
            self.last_set_price_value.write(new_price);
            self.call_count.write(self.call_count.read() + 1);
        }

        #[external(v0)]
        fn claim(ref self: ContractState, land_location: u16) {
            self.last_claim_location.write(land_location);
            self.call_count.write(self.call_count.read() + 1);
        }

        #[external(v0)]
        fn increase_stake(ref self: ContractState, land_location: u16, amount_to_stake: u256) {
            self.last_stake_location.write(land_location);
            self.last_stake_amount.write(amount_to_stake);
            self.call_count.write(self.call_count.read() + 1);
        }

        #[external(v0)]
        fn withdraw_stake(ref self: ContractState, land_location: u16) {
            self.last_withdraw_location.write(land_location);
            self.call_count.write(self.call_count.read() + 1);
        }

        #[external(v0)]
        fn get_call_count(self: @ContractState) -> u32 {
            self.call_count.read()
        }

        #[external(v0)]
        fn get_last_claim_location(self: @ContractState) -> u16 {
            self.last_claim_location.read()
        }

        #[external(v0)]
        fn get_last_buy_location(self: @ContractState) -> u16 {
            self.last_buy_location.read()
        }

        #[external(v0)]
        fn get_last_sell_location(self: @ContractState) -> u16 {
            self.last_sell_location.read()
        }

        #[external(v0)]
        fn get_last_set_price_location(self: @ContractState) -> u16 {
            self.last_set_price_location.read()
        }

        #[external(v0)]
        fn get_last_stake_location(self: @ContractState) -> u16 {
            self.last_stake_location.read()
        }

        #[external(v0)]
        fn get_last_withdraw_location(self: @ContractState) -> u16 {
            self.last_withdraw_location.read()
        }
    }
}
