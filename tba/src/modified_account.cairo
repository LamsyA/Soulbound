use starknet::ClassHash;

#[starknet::interface]
trait IModifiedAccount<TContractState> {
    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
    fn version(self: @TContractState) -> u8;
}

#[starknet::contract(account)]
mod ModifiedAccount {
    use core::starknet::SyscallResultTrait;
    use token_bound_accounts::account::account::AccountComponent::InternalTrait;
    use token_bound_accounts::interfaces::IAccount::IAccount;
    use starknet::{ContractAddress, ClassHash, get_caller_address};
    use token_bound_accounts::account::AccountComponent;
    use super::IModifiedAccount;

    component!(path: AccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl AccountImpl = AccountComponent::AccountImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: AccountComponent::Storage,
        version: u8
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: AccountComponent::Event
    }
}
