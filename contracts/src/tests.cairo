#[cfg(test)]
mod tests {
    use starknet::class_hash::Felt252TryIntoClassHash;
    use debug::PrintTrait;

    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
    use pixelaw::core::models::registry::{app, app_user, app_name, core_actions_address};

    use pixelaw::core::models::pixel::{Pixel, PixelUpdate};
    use pixelaw::core::models::pixel::{pixel};
    use pixelaw::core::models::alert::{alert};
    use pixelaw::core::models::queue::{queue_item};
    use pixelaw::core::models::permissions::{permissions};
    use pixelaw::core::utils::{get_core_actions, Direction, Position, DefaultParameters};
    use pixelaw::core::actions::{actions, IActionsDispatcher, IActionsDispatcherTrait};

    use dojo::test_utils::{spawn_test_world, deploy_contract};

    use tictactoe::app::{
        tic_tac_toe_game, tic_tac_toe_game_field, tictactoe_actions, ITicTacToeActionsDispatcher,
        ITicTacToeActionsDispatcherTrait
    };

    use zeroable::Zeroable;

    // Helper function: deploys world and actions
    fn deploy_world() -> (IWorldDispatcher, IActionsDispatcher, ITicTacToeActionsDispatcher) {
        // Deploy World and models
        let world = spawn_test_world(
            array![
                pixel::TEST_CLASS_HASH,
                app::TEST_CLASS_HASH,
                app_user::TEST_CLASS_HASH,
                app_name::TEST_CLASS_HASH,
                alert::TEST_CLASS_HASH,
                queue_item::TEST_CLASS_HASH,
                core_actions_address::TEST_CLASS_HASH,
                permissions::TEST_CLASS_HASH,
                tic_tac_toe_game::TEST_CLASS_HASH,
                tic_tac_toe_game_field::TEST_CLASS_HASH
            ]
        );

        // Deploy Core actions
        let core_actions_address = world
            .deploy_contract('salt1', actions::TEST_CLASS_HASH.try_into().unwrap());
        let core_actions = IActionsDispatcher { contract_address: core_actions_address };

        // Deploy Tictactoe actions
        let tictactoe_actions_address = world
            .deploy_contract('salt2', tictactoe_actions::TEST_CLASS_HASH.try_into().unwrap());
        let tictactoe_actions = ITicTacToeActionsDispatcher {
            contract_address: tictactoe_actions_address
        };

        // Setup dojo auth
        world.grant_writer('Pixel', core_actions_address);
        world.grant_writer('App', core_actions_address);
        world.grant_writer('AppName', core_actions_address);
        world.grant_writer('CoreActionsAddress', core_actions_address);
        world.grant_writer('Permissions', core_actions_address);

        world.grant_writer('TicTacToeGame', tictactoe_actions_address);
        world.grant_writer('TicTacToeGameField', tictactoe_actions_address);

        (world, core_actions, tictactoe_actions)
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_tictactoe_actions() {
        // Deploy everything
        let (world, core_actions, tictactoe_actions) = deploy_world();

        let dummy_uuid = world.uuid();

        core_actions.init();
        tictactoe_actions.init();

        let player1 = starknet::contract_address_const::<0x1337>();
        starknet::testing::set_account_contract_address(player1);

        // Create the game
        // Pixels 1,1 to 3,3 will be reserved
        tictactoe_actions
            .interact(
                DefaultParameters {
                    for_player: Zeroable::zero(),
                    for_system: Zeroable::zero(),
                    position: Position { x: 1, y: 1 },
                    color: 0
                },
            );

        // Play the first move
        tictactoe_actions
            .play(
                DefaultParameters {
                    for_player: Zeroable::zero(),
                    for_system: Zeroable::zero(),
                    position: Position { x: 1, y: 1 },
                    color: 0xff0000
                },
            );

        let pixel_1_1 = get!(world, (1, 1), (Pixel));
        assert(pixel_1_1.color == 0, 'should be the color');

        'Passed test'.print();
    }
    
}
