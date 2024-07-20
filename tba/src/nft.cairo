// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^0.14.0
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMainNft<TContractState> {
    fn mint(ref self: TContractState, metadata: NFTMetadata, receiver: starknet::ContractAddress);
    fn update_main_contract_addr(ref self: TContractState, main: ContractAddress);
    fn get_meta_data_by_id(ref self: TContractState, token_id : felt252)-> NFTMetadata;
}

#[derive(Drop, Serde, PartialEq, starknet::Store)]
pub struct NFTMetadata {
    name: felt252,
    amount: u128,
    date: u128,
    minter: ContractAddress,
}


#[starknet::contract]
pub mod MyToken {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::token::erc721::ERC721HooksEmptyImpl;
    use starknet::{ContractAddress, get_caller_address};
    use super::NFTMetadata;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        main_addr: ContractAddress,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        nfts: LegacyMap::<felt252, NFTMetadata>,
        token_id: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: ByteArray, symbol: ByteArray) {
        let base_uri = format!("{:?}", get_caller_address());
        self.erc721.initializer(name, symbol, base_uri);
        self.ownable.initializer(get_caller_address());
    }

    #[abi(embed_v0)]
    impl MainNft of super::IMainNft<ContractState> {
        fn mint(ref self: ContractState, metadata: NFTMetadata, receiver: ContractAddress) {
            assert(
                self.main_addr.read() == starknet::get_caller_address(),
                'Only main contract can mint'
            );
            let current_token_id = self.token_id.read();
            self.nfts.write(current_token_id, metadata);
            let current_token_id: u256 = self.token_id.read().try_into().unwrap();
            self.erc721.mint(receiver, current_token_id);
            let current_token_id = self.token_id.read();

            self.token_id.write(current_token_id + 1);
        }

        fn update_main_contract_addr(ref self: ContractState, main: ContractAddress) {
            self.main_addr.write(main);
        }

        fn get_meta_data_by_id(ref self: ContractState, token_id : felt252)-> NFTMetadata{
        self.nfts.read(token_id)
        }
    }
}
