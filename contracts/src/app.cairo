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
    fn human_move(self: @TContractState, default_params: DefaultParameters);
    fn machine_move(self: @TContractState, default_params: DefaultParameters);
    //fn check_winner(self: @TContractState, default_params: DefaultParameters);
    fn ownerless_space(self: @TContractState, default_params: DefaultParameters) -> bool;
    fn available_moves(self: @TContractState, default_params: DefaultParameters) -> u8;
}

#[dojo::contract]
mod tictactoe_actions {
    use starknet::{get_caller_address, get_contract_address, get_execution_info, ContractAddress
    };
    use super::ITicTacToeActions;
    use pixelaw::core::models::pixel::{Pixel, PixelUpdate};
    use pixelaw::core::models::permissions::{Permission};
    use pixelaw::core::actions::{
        IActionsDispatcher as ICoreActionsDispatcher,
        IActionsDispatcherTrait as ICoreActionsDispatcherTrait
    };
    use super::{APP_KEY, APP_ICON, APP_MANIFEST, GAME_MAX_DURATION, TicTacToeGame, State, tictactoe_size};
    use pixelaw::core::utils::{get_core_actions, Position, DefaultParameters};
	use pixelaw::core::models::registry::{App, AppName, CoreActionsAddress};
    use debug::PrintTrait;

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
            
            //functional variables
            let position = default_params.position;
            let mut pixel = get!(world, (position.x, position.y), (Pixel));
            let mut game = get!(world, (position.x, position.y), TicTacToeGame);
            let THIS_APP = get!(world, APP_KEY, (AppName));
            let timestamp = starknet::get_block_timestamp();
            let player = core_actions.get_player_address(default_params.for_player);
            let system = core_actions.get_system_address(default_params.for_system);

			if pixel.app == THIS_APP.system && game.state == State::WAITING_FOR_HUMAN //check if current pixel is a tictactoe pixel and game state
			{
				self.human_move(default_params);
			}
            else if pixel.app == THIS_APP.system && game.state == State::WAITING_FOR_MACHINE //check if current pixel is a tictactoe pixel and game state
			{
				'wait for machine to play'.print();
			}
			else if self.ownerless_space(default_params) == true //check if size grid ownerless;
			{
				let mut id = world.uuid(); //do we need this in this condition?
                game =
                    TicTacToeGame {
                        x: position.x,
                        y: position.y,
                        id,
                        creator: player,
                        state: State::WAITING_FOR_HUMAN,
                        started_timestamp: timestamp
                    };

                emit!(world, GameOpened {game_id: game.id, creator: player});

                set!(world, (game));

                let mut i: u64 = 0;
				let mut j: u64 = 0;
                loop {
					if i >= tictactoe_size {
						break;
					}
					j = 0;
					loop {
						if j >= tictactoe_size {
							break;
						}
						core_actions
							.update_pixel(
							player,
							system,
							PixelUpdate {
								x: position.x + j,
								y: position.y + i,
								color: Option::Some(default_params.color),
								alert: Option::None,
								timestamp: Option::None,
								text: Option::None,
								app: Option::Some(system),
								owner: Option::Some(player),
								action: Option::None,
								}
							);
							j += 1;
					};
					i += 1;
				};
			} else {
				'find a free area'.print();
			}
		}

        fn human_move(self: @ContractState, default_params: DefaultParameters) {
            //core variables
            let world = self.world_dispatcher.read();
            let core_actions = get_core_actions(world);
            
            //functional variables
            let position = default_params.position;
            let mut pixel = get!(world, (position.x, position.y), (Pixel));
            let mut game = get!(world, (position.x, position.y), TicTacToeGame);
            let player = core_actions.get_player_address(default_params.for_player);
            let system = core_actions.get_system_address(default_params.for_system);

            core_actions
                .update_pixel(
                player,
                system,
                PixelUpdate {
                    x: position.x,
                    y: position.y,
                    color: Option::Some(default_params.color),
                    alert: Option::None,
                    timestamp: Option::None,
                    text: Option::Some('U+274C'),
                    app: Option::Some(system),
                    owner: Option::Some(player),
                    action: Option::None,
                    }
                );
            game.state = State::WAITING_FOR_MACHINE;

            self.machine_move(default_params);
        }


        fn machine_move(self: @ContractState, default_params: DefaultParameters) {
            //core variables
            let world = self.world_dispatcher.read();
            let core_actions = get_core_actions(world);
            
            //functional variables
            let position = default_params.position;
            let mut pixel = get!(world, (position.x, position.y), (Pixel));
            let mut game = get!(world, (position.x, position.y), TicTacToeGame);
            let player = core_actions.get_player_address(default_params.for_player);
            let system = core_actions.get_system_address(default_params.for_system);

            //here I would call the model and ask for the optimal move.

            //this is updating the pixelaw state
            core_actions
                .update_pixel(
                player,
                system,
                PixelUpdate {
                    x: position.x,
                    y: position.y,
                    color: Option::Some(default_params.color),
                    alert: Option::None,
                    timestamp: Option::None,
                    text: Option::Some('U+274C'),
                    app: Option::Some(system),
                    owner: Option::Some(player),
                    action: Option::None,
                    }
                );

            if self.available_moves(default_params) == 0 {
                game.state = State::Finished;
            }
            game.state = State::WAITING_FOR_MACHINE;
        }

        fn ownerless_space(self: @ContractState, default_params: DefaultParameters) -> bool {
        let world = self.world_dispatcher.read();
        let core_actions = get_core_actions(world);
        let position = default_params.position;
        let mut pixel = get!(world, (position.x, position.y), (Pixel));

        let mut i: u64 = 0;
        let mut j: u64 = 0;
        let mut check_test: bool = true;

        let check = loop {
            if !(pixel.owner.is_zero() && i <= tictactoe_size)
            {
                break false;
            }
            pixel = get!(world, (position.x, (position.y + i)), (Pixel));
            j = 0;
            loop {
                if !(pixel.owner.is_zero() && j <= tictactoe_size)
                {
                    break false;
                }
                pixel = get!(world, ((position.x + j), position.y), (Pixel));
                j += 1;
            };
            i += 1;
            break true;
        };
        check
        }

        fn available_moves(self: @ContractState, default_params: DefaultParameters) -> u8 {
            let world = self.world_dispatcher.read();
            let test: u8 = 2;
            test
        }
    }
}