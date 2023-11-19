use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use pixelaw::core::models::pixel::{Pixel, PixelUpdate};
use pixelaw::core::utils::{get_core_actions, Direction, Position, DefaultParameters};
use pixelaw::core::models::registry::{App, AppName, CoreActionsAddress};
use starknet::{get_caller_address, get_contract_address, get_execution_info, ContractAddress};
use pixelaw::core::actions::{
    IActionsDispatcher as ICoreActionsDispatcher,
    IActionsDispatcherTrait as ICoreActionsDispatcherTrait
};

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
    started_time: u64,
    x: u64,
    y: u64,
    moves_left: u8
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
    fn check_winner(
        self: @TContractState,
        origin: Position,
        core_actions: ICoreActionsDispatcher,
        default_params: DefaultParameters,
        game_array: Array<u8>
    ) -> u8;
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

    use tictactoe::inference::move_selector;
    use core::array::SpanTrait;
    use orion::operators::tensor::{TensorTrait, FP16x16Tensor, Tensor, FP16x16TensorAdd};
    use orion::operators::nn::{NNTrait, FP16x16NN};
    use orion::numbers::{FP16x16, FixedTrait};

    #[derive(Drop, starknet::Event)]
    struct GameSpawned {
        game_id: u32,
        app: ContractAddress,
        owner: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct GameResult {
        player: ContractAddress,
        result: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct GameOpened {
        game_id: u32,
        creator: ContractAddress
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GameOpened: GameOpened,
        GameResult: GameResult,
        GameSpawned: GameSpawned,
    }

    #[external(v0)]
    impl TicTacToeActionsImpl of ITicTacToeActions<ContractState> {
        fn init(self: @ContractState) {
            let world = self.world_dispatcher.read();
            let core_actions = pixelaw::core::utils::get_core_actions(world);

            core_actions.update_app(APP_KEY, APP_ICON, APP_MANIFEST);
        }

        fn interact(self: @ContractState, default_params: DefaultParameters) -> felt252 {
            'interact: start'.print();
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
                id: game_id,
                player1: player,
                started_time: starknet::get_block_timestamp(),
                x: position.x,
                y: position.y,
                moves_left: 9
            };
            let system = core_actions.get_system_address(default_params.for_system);

            set!(world, (game));
            emit!(world, GameSpawned { 
                game_id: game_id, 
                app: system, 
                owner:player 
            });
            'interact: done'.print();
            'done'
        }

        fn play(self: @ContractState, default_params: DefaultParameters) -> felt252 {
            'play: start'.print();
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
            let mut field = get!(world, (position.x, position.y), TicTacToeGameField);

            // Ensure this pixel was not already used for a move
            assert(field.state == 0, 'field already set');

            // Process the player's move
            field.state = 1;
            set!(world, (field));

            // Change the Pixel
            core_actions
                .update_pixel(
                    player,
                    get_contract_address(),
                    PixelUpdate {
                        x: position.x,
                        y: position.y,
                        color: Option::None,
                        alert: Option::None,
                        timestamp: Option::None,
                        text: Option::Some('U+0058'),
                        app: Option::None,
                        owner: Option::None,
                        action: Option::Some('none')
                    }
                );

            // And load the Game
            let mut game = get!(world, (field.id), TicTacToeGame);
            game.moves_left.print();
            game.moves_left -= 1;
            set!(world, (game));

            // Get the origin pixel
            let origin_position = Position { x: game.x, y: game.y };

            // Determine the game state
            let mut statearray = determine_game_state(world, game.x, game.y);

            // Check if the player won already
            let winner_state = self
                .check_winner(origin_position, core_actions, default_params, statearray.clone());

            if winner_state == 1 {
                // TODO emit event and handle everything properly
                'human winner'.print();
                emit!(world, GameResult { player, result:'human won!' });
                return 'human won!';
            } else if winner_state == 2 {
                'bot winner'.print();
                emit!(world, GameResult { player, result:'bot won!' });
                return 'bot won!';
            } else if winner_state == 0 {
                'tie game'.print();
                emit!(world, GameResult { player, result:'tie game!' });
                return 'tie game!';
            } else if game.moves_left == 0 {
                'Oh.. its a tie'.print();
                emit!(world, GameResult { player, result:'tie game!' });
                return 'tie';
            }

            // Get the AI move
            print_array(statearray.clone());
            let ai_move_index = move_selector(statearray.clone()).unwrap();

            'ai move'.print();
            ai_move_index.print();

            // Handle the AI move
            // Find the pixel belonging to the index returned 
            // index 0 means the top-left pixel 
            let ai_position = position_from(origin_position, ai_move_index);

            // Change the field
            let mut ai_field = get!(world, (ai_position.x, ai_position.y), TicTacToeGameField);
            assert(ai_field.state == 0, 'ai illegal move');
            ai_field.state = 2;
            set!(world, (ai_field));

            // Change the Pixel
            core_actions
                .update_pixel(
                    player,
                    get_contract_address(),
                    PixelUpdate {
                        x: position.x,
                        y: position.y,
                        color: Option::None,
                        alert: Option::None,
                        timestamp: Option::None,
                        text: Option::Some('U+004F'),
                        app: Option::None,
                        owner: Option::None,
                        action: Option::Some('none')
                    }
                );

            // Update the Game object
            game.moves_left -= 1;
            set!(world, (game));

            // Check if the player won already
            let winner_state = self
                .check_winner(origin_position, core_actions, default_params, statearray.clone());

            if winner_state == 1 {
                // TODO emit event and handle everything properly
                'human winner'.print();
                emit!(world, GameResult { player, result:'human won!' });
                return 'human won!';
            } else if winner_state == 2 {
                'bot winner'.print();
                emit!(world, GameResult { player, result:'bot won!' });
                return 'bot won!';
            } else if winner_state == 0 {
                'tie game'.print();
                emit!(world, GameResult { player, result:'tie game!' });
                return 'tie game!';
            } else if game.moves_left == 0 {
                'Oh.. its a tie'.print();
                emit!(world, GameResult { player, result:'tie game!' });
                return 'tie';
            }

            'play: done'.print();
            'done'
        }


        fn check_winner(
            self: @ContractState,
            origin: Position,
            core_actions: ICoreActionsDispatcher,
            default_params: DefaultParameters,
            game_array: Array<u8>
        ) -> u8 {
            let mut player1: u8 = 1;
            let mut result: u8 = 0;
            let mut index = 0;
            let game_array2 = game_array.clone();
            let mut arr: Array<u32> = ArrayTrait::new();

            loop {
                if index == 3 {
                    break;
                }
                // Horizontal check
                if *game_array2.at(3 * index) == *game_array2.at(3 * index + 1)
                    && *game_array2.at(3 * index) == *game_array2.at(3 * index + 2)
                    && *game_array2.at(3 * index) != 0 {
                    result = *game_array2.at(3 * index);

                    arr.append(3 * index);
                    arr.append(3 * index + 1);
                    arr.append(3 * index + 2);
                }

                // Vertical check
                if *game_array2.at(index) == *game_array2.at(index + 3)
                    && *game_array2.at(index) == *game_array2.at(index + 6)
                    && *game_array2.at(index) != 0 {
                    result = *game_array2.at(index);

                    arr.append(index);
                    arr.append(index + 3);
                    arr.append(index + 6);
                }
                index = index + 1;
            };

            let game_array3 = game_array.clone();

            // Diagonals
            if *game_array3.at(0) == *game_array3.at(4)
                && *game_array3.at(0) == *game_array3.at(8)
                && *game_array3.at(0) != 0 {
                result = *game_array3.at(0);
                arr.append(0);
                arr.append(4);
                arr.append(8);
            }

            if *game_array3.at(2) == *game_array3.at(4)
                && *game_array3.at(2) == *game_array3.at(6)
                && *game_array3.at(2) != 0 {
                result = *game_array3.at(2);
                arr.append(2);
                arr.append(4);
                arr.append(6);
            }
            let mut pixel_color: u32 = 0;

            if result == 0 {
                let mut zero_found: bool = false;
                let mut index = 0;
                loop {
                    if index == 8 {
                        break;
                    }
                    if *game_array3.at(index) == 0 {
                        zero_found = true;
                    }
                    index += 1;
                };
                if zero_found {
                    result = 0;
                } else {
                    result = 3;
                }
            } else if (result == 1 || result == 2) && arr.len() == 3 {
                let mut index = 0;
                if result == 1 {
                    // GREEN
                    pixel_color = 0x00ff00;
                } else {
                    // RED
                    pixel_color = 0xff0000;
                }

                let player = core_actions.get_player_address(default_params.for_player);
                let system = core_actions.get_system_address(default_params.for_system);

                loop {
                    if index == 3 {
                        break;
                    }

                    let pixel_position = position_from(origin, *arr.at(index));
                    core_actions
                        .update_pixel(
                            player,
                            system,
                            PixelUpdate {
                                x: pixel_position.x,
                                y: pixel_position.y,
                                color: Option::Some(pixel_color),
                                alert: Option::None,
                                timestamp: Option::None,
                                text: Option::Some('U+0058'),
                                app: Option::None,
                                owner: Option::None,
                                action: Option::Some('none')
                            }
                        );
                    index += 1;
                }
            }

            result
        }
    }


    fn print_array(array: Array<u8>) {
        'printing 9 array:'.print();
        (*array.at(0)).print();
        (*array.at(1)).print();
        (*array.at(2)).print();
        (*array.at(3)).print();
        (*array.at(4)).print();
        (*array.at(5)).print();
        (*array.at(6)).print();
        (*array.at(7)).print();
        (*array.at(8)).print();
        'printing 9 array: end'.print();
    }

    // For a given array index, give the appropriate position
    fn position_from(origin: Position, index: u32) -> Position {
        let mut result = origin.clone();
        result.x = origin.x + (index % 3).into(); // Adjusting for 0-based indexing
        result.y = origin.y + (index / 3).into(); // Adjusting for 0-based indexing
        result
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

                let field = get!(world, (x + j, y + i), TicTacToeGameField);
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
}
