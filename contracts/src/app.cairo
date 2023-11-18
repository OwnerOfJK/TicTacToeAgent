use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use pixelaw::core::models::pixel::{Pixel, PixelUpdate};
use pixelaw::core::utils::{get_core_actions, Direction, Position, DefaultParameters};
use pixelaw::core::models::registry::{App, AppName, CoreActionsAddress};
use starknet::{get_caller_address, get_contract_address, get_execution_info, ContractAddress};


const APP_KEY: felt252 = 'tictactoe';
const APP_ICON: felt252 = 'U+1F4A3';
const GAME_MAX_DURATION: u64 = 20000;
const APP_MANIFEST: felt252 = 'BASE/manifests/tictactoe';
const tictactoe_size: u64 = 3;

#[derive(Serde, Copy, Drop, PartialEq, Introspect)]
enum State {
    None: (),
    WAITING_FOR_HUMAN: (),
    WAITING_FOR_MACHINE: (),
    Finished: ()
}

#[derive(Model, Copy, Drop, Serde, SerdeLen)]
struct TicTacToeGame {
    #[key]
    x: u64,
    #[key]
    y: u64,
    id: u32,
    creator: ContractAddress,
    state: State,
    started_timestamp: u64
}

#[starknet::interface]
trait ITicTacToeActions<TContractState> {
    fn init(self: @TContractState);
    fn interact(self: @TContractState, default_params: DefaultParameters);
}

#[dojo::contract]
mod tictactoe_actions {
    use starknet::{get_caller_address, get_contract_address, get_execution_info, ContractAddress};
    use super::ITicTacToeActions;
    use pixelaw::core::models::pixel::{Pixel, PixelUpdate};
    use pixelaw::core::models::permissions::{Permission};
    use pixelaw::core::actions::{
        IActionsDispatcher as ICoreActionsDispatcher,
        IActionsDispatcherTrait as ICoreActionsDispatcherTrait
    };
    use super::{
        APP_KEY, APP_ICON, APP_MANIFEST, GAME_MAX_DURATION, TicTacToeGame, State, tictactoe_size
    };
    use pixelaw::core::utils::{get_core_actions, Position, DefaultParameters};
    use pixelaw::core::models::registry::{App, AppName, CoreActionsAddress};
    use debug::PrintTrait;

    use tictactoe::inference::predict;
    use core::array::SpanTrait;
    use orion::operators::tensor::{TensorTrait, FP16x16Tensor, Tensor, FP16x16TensorAdd};
    use orion::operators::nn::{NNTrait, FP16x16NN};
    use orion::numbers::{FP16x16, FixedTrait};

    #[derive(Drop, starknet::Event)]
    struct GameOpened {
        game_id: u32,
        creator: ContractAddress
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GameOpened: GameOpened
    }

    #[external(v0)]
    impl TicTacToeActionsImpl of ITicTacToeActions<ContractState> {
        fn init(self: @ContractState) {
            let world = self.world_dispatcher.read();
            let core_actions = pixelaw::core::utils::get_core_actions(world);

            core_actions.update_app(APP_KEY, APP_ICON, APP_MANIFEST);
        }

        fn interact(self: @ContractState, default_params: DefaultParameters) {
            //core variables
            let world = self.world_dispatcher.read();
            let core_actions = get_core_actions(world);

            let mut board = create_test_board();

            let result = predict(board);
            'Result following:'.print();
            result.print();
        }
    }

    fn create_test_board() -> orion::operators::tensor::core::Tensor::<
        orion::numbers::fixed_point::implementations::fp16x16::core::FP16x16
    > {
        let two = FixedTrait::<FP16x16>::new_unscaled(2, false);
        let one = FixedTrait::<FP16x16>::new_unscaled(1, false);
        let zero = FixedTrait::<FP16x16>::new_unscaled(0, false);

        Tensor {
            shape: array![9].span(),
            // data: array![zero, zero, zero, zero, zero, zero, zero, zero, zero].span()
            data: array![one, two, one, two, one, two, one, two, zero].span()
        }
    }
}
