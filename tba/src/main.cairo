//  this contract is the main contract
//  it would ensure people can pay in usdc and stark by transferring to main contract address and the usr gets minted an nft as some form of reciept. if possible the reciept can contain infrmation about the serives paid for ...

// we begin
use starknet::ContractAddress;
use super::nft::{MyToken, NFTMetadata};


#[starknet::interface]
pub trait PayMaster<TContractState> {
    fn pay_with_stark(ref self: TContractState, amount: felt252, metadata: NFTMetadata);
    fn pay_with_usdc(ref self: TContractState, amount: felt252, metadata: NFTMetadata);
    fn pay_with_ether(ref self: TContractState, amount: felt252, metadata: NFTMetadata);
}


#[starknet::contract]
pub mod payMaster {
    use core::num::traits::Zero;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::ContractAddress;
    use super::super::token::{erc20, IERC20Dispatcher, IERC20DispatcherTrait};
    use super::super::nft::{MyToken, IMainNftDispatcher, IMainNftDispatcherTrait};
    use super::NFTMetadata;


    #[storage]
    struct Storage {
        number_of_transactions: felt252,
        usdc_address: ContractAddress,
        ether_address: ContractAddress,
        stark_address: ContractAddress,
        nft_address: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {
        Usdc_Approved: Usdc_Approved,
        Stark_Approved: Stark_Approved,
        Ether_Approved: Ether_Approved
    }

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct Usdc_Approved {
        #[key]
        from: ContractAddress,
        to: ContractAddress,
        amount: felt252
    }

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct Stark_Approved {
        #[key]
        from: ContractAddress,
        to: ContractAddress,
        amount: felt252
    }

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct Ether_Approved {
        #[key]
        from: ContractAddress,
        to: ContractAddress,
        amount: felt252
    }

    mod Errors {
        pub const ADDRESS_FROM_ZERO: felt252 = 'ZERO: Zero Address';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        usdc: ContractAddress,
        ether: ContractAddress,
        stark: ContractAddress,
        nft: ContractAddress
    ) {
        self.usdc_address.write(usdc);
        self.stark_address.write(stark);
        self.ether_address.write(ether);
        self.nft_address.write(nft);
    }

    #[abi(embed_v0)]
    impl PayMasterImpl of super::PayMaster<ContractState> {
        fn pay_with_stark(ref self: ContractState, amount: felt252, metadata: NFTMetadata) {
            let user = get_caller_address();
            let mut count = self.number_of_transactions.read();
            let token = IERC20Dispatcher { contract_address: self.stark_address.read() };
            token.transfer_from(user, get_contract_address(), amount);
            count += 1;
            self.number_of_transactions.write(count);
            self
                .emit(
                    Stark_Approved {
                        from: get_caller_address(), to: get_contract_address(), amount
                    }
                );

            let nftToken = IMainNftDispatcher { contract_address: self.nft_address.read() };
            nftToken.mint(metadata, get_caller_address());
        }
        fn pay_with_usdc(ref self: ContractState, amount: felt252, metadata: NFTMetadata) {
            let user = get_caller_address();
            let mut count = self.number_of_transactions.read();
            let token = IERC20Dispatcher { contract_address: self.usdc_address.read() };
            token.transfer_from(user, get_contract_address(), amount);
            count += 1;
            self.number_of_transactions.write(count);
            self
                .emit(
                    Usdc_Approved { from: get_caller_address(), to: get_contract_address(), amount }
                );

            let nftToken = IMainNftDispatcher { contract_address: self.nft_address.read() };
            nftToken.mint(metadata, get_caller_address());
        }
        fn pay_with_ether(ref self: ContractState, amount: felt252, metadata: NFTMetadata) {
            let user = get_caller_address();
            let mut count = self.number_of_transactions.read();
            let token = IERC20Dispatcher { contract_address: self.ether_address.read() };
            token.transfer_from(user, get_contract_address(), amount);
            count += 1;
            self.number_of_transactions.write(count);
            self
                .emit(
                    Ether_Approved {
                        from: get_caller_address(), to: get_contract_address(), amount
                    }
                );
            let nftToken = IMainNftDispatcher { contract_address: self.nft_address.read() };
            nftToken.mint(metadata, get_caller_address());
        }
    }
}

