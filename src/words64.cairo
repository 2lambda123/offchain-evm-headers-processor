from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math import assert_le, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.alloc import alloc

from src.bitshift import bitshift_right, bitshift_left
from src.types import IntsSequence
from starkware.cairo.common.pow import pow

func extract_byte{range_check_ptr}(word: felt, word_len_bytes: felt, position: felt) -> (
    res: felt
) {
    alloc_locals;
    assert_le(position, word_len_bytes - 1);  // Ensures that the extracted byte is not out of word range
    local tailcut_shift = (word_len_bytes - 1 - position) * 8;
    let (local removed_tail) = bitshift_right(word, tailcut_shift);
    local headcut_shift = (word_len_bytes - position) * 8;
    if (headcut_shift == 64) {
        return (removed_tail,);
    }
    let (local removed_head) = bitshift_left(removed_tail, 56);
    let (local removed_zeros) = bitshift_right(removed_head, 56);
    return (removed_zeros,);
}

func extract_bytes{range_check_ptr}(word: felt, word_len_bytes: felt, position: felt, number_of_bytes: felt) -> (
    res: felt
) {
    alloc_locals;
    assert_le(position, word_len_bytes - number_of_bytes);
    local left_shift_bytes = position;
    let (local left_shifted) = bitshift_left(word, left_shift_bytes * 8);
    local right_shift_bytes = word_len_bytes - number_of_bytes;
    let (local right_shifted) = bitshift_right(left_shifted, right_shift_bytes * 8);
    return (right_shifted, );
}

func extract_nibble{range_check_ptr}(word: felt, word_len_bytes: felt, position: felt) -> (
    res: felt
) {
    assert_le(position, (word_len_bytes * 2) - 1);  // Ensures that the extracted nibble is not out of word range
    let (shifted) = bitshift_right(word, (word_len_bytes * 2 - 1) * 4 - position * 4);
    let (_, nibble) = unsigned_div_rem(shifted, 0x10);
    return (nibble,);
}

func extract_nibble_from_words{range_check_ptr}(input: IntsSequence, position: felt) -> (
    res: felt
) {
    alloc_locals;
    let (word_index, nibble_index) = unsigned_div_rem(position, 16);

    // Is 0 when it is last word
    let is_last_word = input.element_size_words - word_index - 1;

    if (is_last_word == 0) {
        let (_, last_word_len) = unsigned_div_rem(input.element_size_bytes, 8);
        local proper_len;

        if (last_word_len == 0) {
            proper_len = 8;
        } else {
            proper_len = last_word_len;
        }

        return extract_nibble(input.element[word_index], proper_len, nibble_index);
    } else {
        return extract_nibble(input.element[word_index], 8, nibble_index);
    }
}

func to_words128{range_check_ptr}(words64: IntsSequence) -> (words128: felt*, words128_len: felt) {
    alloc_locals;
    let (local words128) = alloc();
    return to_words128_rec(words64, words128, 0, 0, 0);
}

func to_words128_rec{range_check_ptr}(
    words64: IntsSequence,
    acc: felt*,
    acc_len: felt,
    current_word_index: felt,
    current_byte_index: felt,
) -> (words128: felt*, words128_len: felt) {
    alloc_locals;
    local exit = is_le(words64.element_size_words, current_word_index);

    if (exit == 1) {
        return (acc, acc_len);
    }

    local is_last_16bytes = is_le(words64.element_size_bytes, current_byte_index + 16);

    if (is_last_16bytes == 1) {
        local bytes_remaining = words64.element_size_bytes - current_byte_index;
        local nonfull_words = is_le(8, bytes_remaining - 1);

        if (nonfull_words == 1) {
            local bit_size = (bytes_remaining - 8) * 8;
            let (local multiplicator) = pow(2, bit_size);
            local left_part = words64.element[current_word_index] * multiplicator;
            local original = words64.element[current_word_index];
            local word128 = left_part + words64.element[current_word_index + 1];
            assert acc[acc_len] = word128;
            return to_words128_rec(
                words64,
                acc,
                acc_len + 1,
                current_word_index + 2,
                current_byte_index + bytes_remaining,
            );
        } else {
            local word128 = words64.element[current_word_index];
            assert acc[acc_len] = word128;
            return to_words128_rec(
                words64, acc, acc_len + 1, current_word_index + 2, current_byte_index + 8
            );
        }
    } else {
        let (local multiplicator) = pow(2, 64);
        local left_part = words64.element[current_word_index] * multiplicator;
        local original = words64.element[current_word_index];
        local word128 = left_part + words64.element[current_word_index + 1];
        assert acc[acc_len] = word128;
        return to_words128_rec(
            words64, acc, acc_len + 1, current_word_index + 2, current_byte_index + 16
        );
    }
}
