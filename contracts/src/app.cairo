use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use pixelaw::core::models::pixel::{Pixel, PixelUpdate};
use pixelaw::core::utils::{get_core_actions, Direction, Position, DefaultParameters};
use pixelaw::core::models::registry::{App, AppName, CoreActionsAddress};
use starknet::{get_caller_address, get_contract_address, get_execution_info, ContractAddress};


const APP_KEY: felt252 = 'tictactoe';
const APP_ICON: felt252 = 'U+1F4A3';
const GAME_MAX_DURATION: u64 = 20000;
const APP_MANIFEST: felt252 = 'BASE/manifests/tictactoe';
const GAME_GRIDSIZE: u64 = 3;


#[derive(Model, Copy, Drop, Serde, SerdeLen)]
struct TicTacToeGame {
    #[key]
    id: u32,
    player1: ContractAddress,
    player2: ContractAddress,
    started_time: u64,
    x: u64,
    y: u64
}

#[derive(Model, Copy, Drop, Serde, SerdeLen)]
struct TicTacToeGameField {
    #[key]
    x: u64,
    #[key]
    y: u64,
    id: u32,
    index: u8,
    state: u8
}


// TODO GameFieldElement struct for each field (since Core has no "data" field)

#[starknet::interface]
trait ITicTacToeActions<TContractState> {
    fn init(self: @TContractState);
    fn interact(self: @TContractState, default_params: DefaultParameters) -> felt252;
    fn play(self: @TContractState, default_params: DefaultParameters) -> felt252;
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
        APP_KEY, APP_ICON, APP_MANIFEST, GAME_MAX_DURATION, TicTacToeGame, TicTacToeGameField,
        GAME_GRIDSIZE
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

        fn interact(self: @ContractState, default_params: DefaultParameters) -> felt252 {
            // Load important variables
            let world = self.world_dispatcher.read();
            let core_actions = get_core_actions(world);
            let position = default_params.position;
            let player = core_actions.get_player_address(default_params.for_player);
            let system = core_actions.get_system_address(default_params.for_system);

            let game_id = world.uuid();

            try_game_setup(
                world, core_actions, system, player, game_id, position, default_params.color
            );

            let game = TicTacToeGame {
                id: world.uuid(),
                player1: player,
                player2: Zeroable::zero(),
                started_time: starknet::get_block_timestamp(),
                x: position.x,
                y: position.y
            };

            set!(world, (game));

            'done'
        }

        fn play(self: @ContractState, default_params: DefaultParameters) -> felt252 {
            // Load important variables
            let world = self.world_dispatcher.read();
            let core_actions = get_core_actions(world);
            let position = default_params.position;
            let player = core_actions.get_player_address(default_params.for_player);
            let system = core_actions.get_system_address(default_params.for_system);

            // Load the Pixel that was clicked
            let mut pixel = get!(world, (position.x, position.y), (Pixel));

            // Ensure the clicked pixel is a TTT 
            assert(pixel.app == get_contract_address(), 'not a TTT app pixel');

            // And load the corresponding GameField
            let field = get!(world, (position.x, position.y), TicTacToeGameField);

            // And load the Game
            let game = get!(world, (field.id), TicTacToeGame);

            // Determine the game state
            // Loop all the pixels, starting with the main
            let statearray = determine_game_state(world, game.x, game.y);

            'done'
        }
    }

    fn determine_game_state(world: IWorldDispatcher, x: u64, y: u64) -> Array<u8> {
        let mut result = array![];
        let mut i: u64 = 0;
        let mut j: u64 = 0;
        loop {
            if i >= GAME_GRIDSIZE {
                break;
            }
            j = 0;
            loop {
                if j >= GAME_GRIDSIZE {
                    break;
                }

                let field = get!(world, (x + i, y + j), TicTacToeGameField);
                result.append(field.state);

                j += 1;
            };
            i += 1;
        };
        result
    }

    fn try_game_setup(
        world: IWorldDispatcher,
        core_actions: ICoreActionsDispatcher,
        system: ContractAddress,
        player: ContractAddress,
        game_id: u32,
        position: Position,
        color: u32
    ) {
        let mut x: u64 = 0;
        let mut y: u64 = 0;
        loop {
            if x >= GAME_GRIDSIZE {
                break;
            }
            y = 0;
            loop {
                if y >= GAME_GRIDSIZE {
                    break;
                }

                let pixel = get!(world, (position.x + x, position.y + y), Pixel);
                assert(pixel.owner.is_zero(), 'No 9 free pixels!');

                y += 1;
            };
            x += 1;
        };

        x = 0;
        y = 0;
        let mut index = 0;

        loop {
            if x >= GAME_GRIDSIZE {
                break;
            }
            y = 0;
            loop {
                if y >= GAME_GRIDSIZE {
                    break;
                }

                core_actions
                    .update_pixel(
                        player,
                        system,
                        PixelUpdate {
                            x: position.x + x,
                            y: position.y + y,
                            color: Option::Some(color),
                            alert: Option::None,
                            timestamp: Option::None,
                            text: Option::None,
                            app: Option::Some(system),
                            owner: Option::Some(player),
                            action: Option::Some('play'),
                        }
                    );

                set!(
                    world,
                    (TicTacToeGameField {
                        x: position.x + x, y: position.y + y, id: game_id, index, state: 0
                    })
                );

                index += 1;
                y += 1;
            };
            x += 1;
        };
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
