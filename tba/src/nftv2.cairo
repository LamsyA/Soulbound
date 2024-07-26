// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^0.14.0
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMainNft<TContractState> {
    fn mint(ref self: TContractState, receiver: starknet::ContractAddress);
    fn set_owner(ref self: TContractState, owner: ContractAddress);
}


#[starknet::contract]
pub mod MyToken {
    use core::option::OptionTrait;
use core::traits::TryInto;
use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::token::erc721::ERC721HooksEmptyImpl;
    use starknet::{ContractAddress, get_caller_address};
    use core::num::traits::Zero;
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
        token_id: felt252,
        owner: ContractAddress
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
    fn constructor(ref self: ContractState) {
        let base_uri = format!("{:?}", get_caller_address());
        let  name: ByteArray = "TNFT";
        let symbol: ByteArray = "TFT";
        self.erc721.initializer(name, symbol, base_uri);
        self.ownable.initializer(get_caller_address());
    }

    #[abi(embed_v0)]
    impl MainNft of super::IMainNft<ContractState> {
        fn mint(ref self: ContractState, receiver: ContractAddress) {
            // assert(get_caller_address() == self.owner.read(), 'not owner');
           
            let current_token_id: u256 = self.token_id.read().try_into().unwrap();
            self.erc721.mint(receiver, current_token_id);
            let current_token_id = self.token_id.read();

            self.token_id.write(current_token_id + 1);
        }

    fn set_owner(ref self: ContractState, owner: ContractAddress){
    assert(self.owner.read() == Zero::zero(), 'owner already set');
    self.owner.write(owner);
    }
      
    }
}
