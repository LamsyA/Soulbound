use starknet::ContractAddress;
use super::nftv2::{MyToken};

#[starknet::interface]
pub trait IStakingContract<TContractState> {
    fn set_reward_amount(ref self: TContractState, amount: u256);
    fn set_reward_duration(ref self: TContractState, duration: u256);
    fn stake(ref self: TContractState, amount: u256);
    fn withdraw(ref self: TContractState, amount: u256, tokenBoundAccount: ContractAddress);
    fn get_rewards(self: @TContractState, account: ContractAddress) -> u256;
    fn claim_rewards(ref self: TContractState);
}

mod Errors {
    pub const NULL_REWARDS: felt252 = 'Reward amount must be > 0';
    pub const NOT_ENOUGH_REWARDS: felt252 = 'Reward amount must be > balance';
    pub const NULL_AMOUNT: felt252 = 'Amount must be > 0';
    pub const NULL_DURATION: felt252 = 'Duration must be > 0';
    pub const UNFINISHED_DURATION: felt252 = 'Reward duration not finished';
    pub const NOT_OWNER: felt252 = 'Caller is not the owner';
    pub const NOT_ENOUGH_BALANCE: felt252 = 'Balance too low';
}

#[starknet::contract]
pub mod StakingContract {
    use core::starknet::event::EventEmitter;
    use core::traits::Into;
    use core::num::traits::Zero;
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use super::super::nftv2::{MyToken, IMainNftDispatcher, IMainNftDispatcherTrait};
    #[storage]
    struct Storage {
        staking_token: IERC20Dispatcher,
        reward_token: IERC20Dispatcher,
        owner: ContractAddress,
        reward_rate: u256,
        duration: u256,
        current_reward_per_staked_token: u256,
        finish_at: u256,
        // last time an operation (staking / withdrawal / rewards claimed) was registered
        last_updated_at: u256,
        last_user_reward_per_staked_token: LegacyMap::<ContractAddress, u256>,
        unclaimed_rewards: LegacyMap::<ContractAddress, u256>,
        total_distributed_rewards: u256,
        // total amount of staked tokens
        total_supply: u256,
        // amount of staked tokens per user
        balance_of: LegacyMap::<ContractAddress, u256>,
        nft_address: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {
        Deposit: Deposit,
        Withdrawal: Withdrawal,
        RewardsFinished: RewardsFinished,
    }

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct Deposit {
        pub user: ContractAddress,
        pub amount: u256,
    }

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct Withdrawal {
        pub user: ContractAddress,
        pub amount: u256,
    }

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct RewardsFinished {
        pub msg: felt252,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        staking_token_address: ContractAddress,
        reward_token_address: ContractAddress,
        nft: ContractAddress
    ) {
        self.staking_token.write(IERC20Dispatcher { contract_address: staking_token_address });
        self.reward_token.write(IERC20Dispatcher { contract_address: reward_token_address });

        self.owner.write(get_caller_address());
        self.nft_address.write(nft);
    }

    #[abi(embed_v0)]
    impl StakingContract of super::IStakingContract<ContractState> {
        fn set_reward_duration(ref self: ContractState, duration: u256) {
            // self.only_owner();

            assert(duration > 0, super::Errors::NULL_DURATION);

            // can only set duration if the previous duration has already finished
            assert(
                self.finish_at.read() < get_block_timestamp().into(),
                super::Errors::UNFINISHED_DURATION
            );

            self.duration.write(duration);
        }

        fn set_reward_amount(ref self: ContractState, amount: u256) {
            // self.only_owner();
            self.update_rewards(Zero::zero());

            assert(amount > 0, super::Errors::NULL_REWARDS);
            assert(self.duration.read() > 0, super::Errors::NULL_DURATION);

            let block_timestamp: u256 = get_block_timestamp().into();

            let rate = if self.finish_at.read() < block_timestamp {
                amount / self.duration.read()
            } else {
                let remaining_rewards = self.reward_rate.read()
                    * (self.finish_at.read() - block_timestamp);
                (remaining_rewards + amount) / self.duration.read()
            };

            assert(
                self.reward_token.read().balance_of(get_contract_address()) >= rate
                    * self.duration.read(),
                super::Errors::NOT_ENOUGH_REWARDS
            );

            self.reward_rate.write(rate);

            // even if the previous reward duration has not finished, we reset the finish_at variable
            self.finish_at.write(block_timestamp + self.duration.read());
            self.last_updated_at.write(block_timestamp);

            // reset total distributed rewards
            self.total_distributed_rewards.write(0);
        }

        fn stake(ref self: ContractState, amount: u256) {
            assert(amount > 0, super::Errors::NULL_AMOUNT);

            let user = get_caller_address();
            self.update_rewards(user);

            self.balance_of.write(user, self.balance_of.read(user) + amount);
            self.total_supply.write(self.total_supply.read() + amount);
            self.staking_token.read().transfer_from(user, get_contract_address(), amount);
 let nftToken = IMainNftDispatcher { contract_address: self.nft_address.read() };
            nftToken.mint(get_caller_address());
            self.emit(Deposit { user, amount });
        }

        fn withdraw(ref self: ContractState, amount: u256, tokenBoundAccount: ContractAddress) {
            assert(amount > 0, super::Errors::NULL_AMOUNT);

            let user = get_caller_address();

            assert(
                self.staking_token.read().balance_of(user) >= amount,
                super::Errors::NOT_ENOUGH_BALANCE
            );

            self.update_rewards(user);

            self.balance_of.write(user, self.balance_of.read(user) - amount);
            self.total_supply.write(self.total_supply.read() - amount);
            self.staking_token.read().transfer(tokenBoundAccount, amount);

            self.emit(Withdrawal { user, amount });
        }

        fn get_rewards(self: @ContractState, account: ContractAddress) -> u256 {
            self.unclaimed_rewards.read(account) + self.compute_new_rewards(account)
        }

        fn claim_rewards(ref self: ContractState) {
            let user = get_caller_address();
            self.update_rewards(user);

            let rewards = self.unclaimed_rewards.read(user);

            if rewards > 0 {
                self.unclaimed_rewards.write(user, 0);
                self.reward_token.read().transfer(user, rewards);
            }
        }
    }

    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
        // call this function every time a user (including owner) performs a state-modifying action
        fn update_rewards(ref self: ContractState, account: ContractAddress) {
            self
                .current_reward_per_staked_token
                .write(self.compute_current_reward_per_staked_token());

            self.last_updated_at.write(self.last_time_applicable());

            if account.is_non_zero() {
                self.distribute_user_rewards(account);

                self
                    .last_user_reward_per_staked_token
                    .write(account, self.current_reward_per_staked_token.read());

                self.send_rewards_finished_event();
            }
        }

        fn distribute_user_rewards(ref self: ContractState, account: ContractAddress) {
            // compute earned rewards since last update for the user `account`
            let user_rewards = self.get_rewards(account);
            self.unclaimed_rewards.write(account, user_rewards);

            // track amount of total rewards distributed
            self
                .total_distributed_rewards
                .write(self.total_distributed_rewards.read() + user_rewards);
        }

        fn send_rewards_finished_event(ref self: ContractState) {
            // check whether we should send a RewardsFinished event
            if self.last_updated_at.read() == self.finish_at.read() {
                let total_rewards = self.reward_rate.read() * self.duration.read();

                if total_rewards != 0 && self.total_distributed_rewards.read() == total_rewards {
                    // owner should set up NEW rewards into the contract
                    self.emit(RewardsFinished { msg: 'Rewards all distributed' });
                } else {
                    // owner should set up rewards into the contract (or add duration by setting up rewards)
                    self.emit(RewardsFinished { msg: 'Rewards not active yet' });
                }
            }
        }

        fn compute_current_reward_per_staked_token(self: @ContractState) -> u256 {
            if self.total_supply.read() == 0 {
                self.current_reward_per_staked_token.read()
            } else {
                self.current_reward_per_staked_token.read()
                    + self.reward_rate.read()
                        * (self.last_time_applicable() - self.last_updated_at.read())
                        / self.total_supply.read()
            }
        }

        fn compute_new_rewards(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of.read(account)
                * (self.current_reward_per_staked_token.read()
                    - self.last_user_reward_per_staked_token.read(account))
        }

        #[inline(always)]
        fn last_time_applicable(self: @ContractState) -> u256 {
            PrivateFunctions::min(self.finish_at.read(), get_block_timestamp().into())
        }

        #[inline(always)]
        fn min(x: u256, y: u256) -> u256 {
            if (x <= y) {
                x
            } else {
                y
            }
        }

        fn only_owner(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), super::Errors::NOT_OWNER);
        }
    }
}

