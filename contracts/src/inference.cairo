// Orion and ML stuff
use core::array::SpanTrait;
use core::array::ArrayTrait;
use orion::operators::tensor::{TensorTrait, FP16x16Tensor, Tensor, FP16x16TensorAdd};
use orion::operators::nn::{NNTrait, FP16x16NN};
use orion::numbers::{FP16x16, FixedTrait};

use sequential_1_dense_1_matmul_readvariableop_0::tensor as t1;
use sequential_1_dense_1_biasadd_readvariableop_0::tensor as t2;
use sequential_1_dense_2_matmul_readvariableop_0::tensor as t3;
use sequential_1_dense_2_biasadd_readvariableop_0::tensor as t4;
use sequential_1_dense_3_matmul_readvariableop_0::tensor as t5;
use sequential_1_dense_3_biasadd_readvariableop_0::tensor as t6;

const MOVE_PLAYER0: u8 = 1;
const MOVE_PLAYER1: u8 = 2;
const MOVE_EMPTY: u8 = 0;

const MODEL_MOVE_PLAYER0: u8 = 0;
const MODEL_MOVE_PLAYER1: u8 = 1;
const MODEL_MOVE_EMPTY: u8 = 2;

fn predict(mut x: Tensor<FP16x16>) -> FP16x16 {
    // let two = FixedTrait::<FP16x16>::new_unscaled(2, false);
    // let mut x = Tensor {
    //     shape: array![9].span(),
    //     data: array![two, two, two, two, two, two, two, two, two].span()
    // };

    // DENSE 1
    x = TensorTrait::matmul(@x, @t1());
    x = x + t2();
    x = NNTrait::relu(@x);

    // DENSE 2
    x = TensorTrait::matmul(@x, @t3());
    x = x + t4();
    x = NNTrait::relu(@x);

    // DENSE 3
    x = TensorTrait::matmul(@x, @t5());
    x = x + t6();

    return *x.data.at(0);
}

// def legal_moves_generator(current_board_state,turn_monitor):
//     """Function that returns the set of all possible legal moves and resulting board states, 
//     for a given input board state and player

//     Args:
//     current_board_state: The current board state
//     turn_monitor: 1 if it's the player who places the mark 1's turn to play, 0 if its his opponent's turn

//     Returns:
//     legal_moves_dict: A dictionary of a list of possible next coordinate-resulting board state pairs
//     The resulting board state is flattened to 1 d array

//     """
//     legal_moves_dict={}
//     for i in range(current_board_state.shape[0]):
//         for j in range(current_board_state.shape[1]):
//             if current_board_state[i,j]==2:
//                 board_state_copy=current_board_state.copy()
//                 board_state_copy[i,j]=turn_monitor
//                 legal_moves_dict[(i,j)]=board_state_copy.flatten()
//     return legal_moves_dict
fn legal_moves_generator(
    current_board_state: @Array<u8>, turn_monitor: u8
) -> Array<(Array<u8>, u32)> {
    let mut moves = ArrayTrait::new();
    let mut index = 0;
    loop {
        if index == 3 * 3 {
            break;
        }
        // loop body
        if *current_board_state.at(index) == MOVE_EMPTY {
            let board_state_copy = modify_array_at_index(
                current_board_state, index, turn_monitor.into()
            );
            moves.append((board_state_copy, index));
        }
        // end of loop body
        index += 1;
    };
    moves
}

fn modify_array_at_index(array: @Array<u8>, index: u32, value: u8) -> Array<u8> {
    let l = array.len();
    let mut new_array = ArrayTrait::new();
    let mut i = 0;
    loop {
        if i >= l {
            break;
        }
        new_array.append(if i == index {
            value
        } else {
            *array.at(i)
        });
        i += 1;
    };
    new_array
}

fn move_selector(current_board_state: Array<u8>) -> Option<u32> { // index of the move
    let turn_monitor = MOVE_PLAYER1;

    let mut current_max_location = 0;
    let mut current_max = FixedTrait::<FP16x16>::new_unscaled(1000, true); // -1000
    let legal_moves = legal_moves_generator(@current_board_state, turn_monitor);
    let mut found = false;

    let mut i = 0;
    loop {
        if (i >= legal_moves.len()) {
            break;
        }

        let (state_after, location) = legal_moves.at(i);

        // get tensor representation of a board state
        let mut tensor_state_after = board_state_to_tensor(state_after);

        let value = predict(tensor_state_after);

        // compare prediction with a previous one
        if value >= current_max {
            // set current prediction and index to max prediction
            current_max = value;
            current_max_location = *location;
            found = true;
        }
        i += 1;
    };
    // return the move in the index
    if (found) {
        Option::Some(current_max_location)
    } else {
        Option::None
    }
}

// TODO impl Into<Array<u8>, Tensor>
fn board_state_to_tensor(board_state: @Array<u8>) -> Tensor<FP16x16> {
    // TODO globals?
    let p0 = FixedTrait::<FP16x16>::new_unscaled(MODEL_MOVE_PLAYER0.into(), false);
    let p1 = FixedTrait::<FP16x16>::new_unscaled(MODEL_MOVE_PLAYER1.into(), false);
    let empty = FixedTrait::<FP16x16>::new_unscaled(MODEL_MOVE_EMPTY.into(), false);

    let mut tensor_data = ArrayTrait::new();

    let mut i = 0;
    loop {
        if i >= board_state.len() {
            break;
        }
        tensor_data
            .append(
                // TODO use enum with Into<u8> and match on it
                if *board_state.at(i) == MOVE_PLAYER0 {
                    p0
                } else if *board_state.at(i) == MOVE_PLAYER1 {
                    p1
                } else {
                    empty
                }
            );
        i += 1;
    };

    Tensor { shape: array![9].span(), data: tensor_data.span() }
}

#[cfg(test)]
mod tests {
    use debug::PrintTrait;
    use super::{MOVE_PLAYER0, MOVE_PLAYER1, MOVE_EMPTY, MODEL_MOVE_PLAYER0, MODEL_MOVE_PLAYER1, MODEL_MOVE_EMPTY};
    use orion::numbers::{FP16x16, FixedTrait};
    #[test]
    #[available_gas(2000000000000)]
    fn test_modify_array_at_index() {
        let arr = array![1, 2, 3];
        let new_arr = super::modify_array_at_index(@arr, 1, 5);
        assert(*new_arr.at(0) == 1, 'wrong value at index 0');
        assert(*new_arr.at(1) == 5, 'wrong value at index 1');
        assert(*new_arr.at(2) == 3, 'wrong value at index 2');
    }

    #[test]
    #[available_gas(2000000000000)]
    fn test_legal_moves_generator() {
        let board = array![
            MOVE_PLAYER0,
            MOVE_PLAYER0,
            MOVE_EMPTY,
            MOVE_PLAYER1,
            MOVE_PLAYER1,
            MOVE_PLAYER0,
            MOVE_PLAYER0,
            MOVE_EMPTY,
            MOVE_PLAYER1,
        ];
        let moves = super::legal_moves_generator(@board, MOVE_PLAYER0);

        assert(moves.len() == 2, 'wrong moves len');

        let (move0, loc0) = moves.at(0);
        let (move1, loc1) = moves.at(1);

        assert(*loc0 == 2, 'wrong location 0');
        assert(*loc1 == 7, 'wrong location 1');

        assert(*move0.at(0) == MOVE_PLAYER0, 'wrong value at move 0 index 0');
        assert(*move0.at(1) == MOVE_PLAYER0, 'wrong value at move 0 index 1');
        assert(*move0.at(2) == MOVE_PLAYER0, 'wrong value at move 0 index 2');
        assert(*move0.at(3) == MOVE_PLAYER1, 'wrong value at move 0 index 3');
        assert(*move0.at(4) == MOVE_PLAYER1, 'wrong value at move 0 index 4');
        assert(*move0.at(5) == MOVE_PLAYER0, 'wrong value at move 0 index 5');
        assert(*move0.at(6) == MOVE_PLAYER0, 'wrong value at move 0 index 6');
        assert(*move0.at(7) == MOVE_EMPTY, 'wrong value at move 0 index 7');
        assert(*move0.at(8) == MOVE_PLAYER1, 'wrong value at move 0 index 8');

        assert(*move1.at(0) == MOVE_PLAYER0, 'wrong value at move 1 index 0');
        assert(*move1.at(1) == MOVE_PLAYER0, 'wrong value at move 1 index 1');
        assert(*move1.at(2) == MOVE_EMPTY, 'wrong value at move 1 index 2');
        assert(*move1.at(3) == MOVE_PLAYER1, 'wrong value at move 1 index 3');
        assert(*move1.at(4) == MOVE_PLAYER1, 'wrong value at move 1 index 4');
        assert(*move1.at(5) == MOVE_PLAYER0, 'wrong value at move 1 index 5');
        assert(*move1.at(6) == MOVE_PLAYER0, 'wrong value at move 1 index 6');
        assert(*move1.at(7) == MOVE_PLAYER0, 'wrong value at move 1 index 7');
        assert(*move1.at(8) == MOVE_PLAYER1, 'wrong value at move 1 index 8');
    }

    #[test]
    #[available_gas(2000000000000)]
    fn test_board_state_to_tensor() {
        let board = array![
            MOVE_PLAYER0,
            MOVE_PLAYER0,
            MOVE_EMPTY,
            MOVE_PLAYER1,
            MOVE_PLAYER1,
            MOVE_PLAYER0,
            MOVE_PLAYER0,
            MOVE_EMPTY,
            MOVE_PLAYER1,
        ];
        let tensor = super::board_state_to_tensor(@board);

        // TODO
        // assert(tensor.shape(0) == 9, 'wrong tensor shape');

        let p0 = FixedTrait::<FP16x16>::new_unscaled(MODEL_MOVE_PLAYER0.into(), false);
        let p1 = FixedTrait::<FP16x16>::new_unscaled(MODEL_MOVE_PLAYER1.into(), false);
        let empty = FixedTrait::<FP16x16>::new_unscaled(MODEL_MOVE_EMPTY.into(), false);

        assert(*tensor.data.at(0) == p0, 'wrong value at index 0');
        assert(*tensor.data.at(1) == p0, 'wrong value at index 1');
        assert(*tensor.data.at(2) == empty, 'wrong value at index 2');
        assert(*tensor.data.at(3) == p1, 'wrong value at index 3');
        assert(*tensor.data.at(4) == p1, 'wrong value at index 4');
        assert(*tensor.data.at(5) == p0, 'wrong value at index 5');
        assert(*tensor.data.at(6) == p0, 'wrong value at index 6');
        assert(*tensor.data.at(7) == empty, 'wrong value at index 7');
        assert(*tensor.data.at(8) == p1, 'wrong value at index 8');
    }

    #[test]
    #[available_gas(2000000000000)]
    fn test_move_selector() {
        // The state looks like this:
        // o x o
        // o x _
        // x _ o
        //

        let state = array![
            MOVE_PLAYER0,
            MOVE_PLAYER1,
            MOVE_PLAYER0,
            MOVE_PLAYER0,
            MOVE_PLAYER1,
            MOVE_EMPTY,
            MOVE_PLAYER1,
            MOVE_EMPTY,
            MOVE_PLAYER0,
        ];

        let move = super::move_selector(state).unwrap();

        assert(move == 7, 'bad move');
    }

    #[test]
    #[available_gas(2000000000000)]
    fn test_only_one_move() {
        // The state looks like this:
        // o _ _
        // _ _ _
        // _ _ _
        //

        let state = array![
            MOVE_PLAYER0,
            MOVE_EMPTY,
            MOVE_EMPTY,
            MOVE_EMPTY,
            MOVE_EMPTY,
            MOVE_EMPTY,
            MOVE_EMPTY,
            MOVE_EMPTY,
            MOVE_EMPTY,
        ];

        let current_player = MOVE_PLAYER1;

        let move = super::move_selector(state).unwrap();

        assert(move != 0, 'bad move');
    }
}
