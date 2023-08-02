from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.math import unsigned_div_rem as felt_divmod
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.alloc import alloc

const div_32 = 2 ** 32;
const div_32_minus_1 = div_32 - 1;

// y MUST be a power of 2
func bitwise_divmod{bitwise_ptr: BitwiseBuiltin*}(x: felt, y: felt) -> (q: felt, r: felt) {
    assert bitwise_ptr.x = x;
    assert bitwise_ptr.y = y - 1;
    let x_and_y = bitwise_ptr.x_and_y;

    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;
    return (q=(x - x_and_y) / y, r=x_and_y);
}

func felt_divmod_2pow32{range_check_ptr}(value: felt) -> (q: felt, r: felt) {
    let r = [range_check_ptr];
    let q = [range_check_ptr + 1];
    %{
        from starkware.cairo.common.math_utils import assert_integer
        assert_integer(ids.div_32)
        assert 0 < ids.div_32 <= PRIME // range_check_builtin.bound, \
            f'div={hex(ids.div_32)} is out of the valid range.'
        ids.q, ids.r = divmod(ids.value, ids.div_32)
    %}
    assert [range_check_ptr + 2] = div_32_minus_1 - r;
    let range_check_ptr = range_check_ptr + 3;

    assert value = q * div_32 + r;
    return (q, r);
}

func felt_divmod_no_input_check{range_check_ptr}(value, div) -> (q: felt, r: felt) {
    // let r = [range_check_ptr];
    // let q = [range_check_ptr + 1];
    // let range_check_ptr = range_check_ptr + 2;
    alloc_locals;
    local r;
    local q;
    %{
        from starkware.cairo.common.math_utils import assert_integer
        assert_integer(ids.div)
        assert 0 < ids.div <= PRIME // range_check_builtin.bound, \
            f'div={hex(ids.div)} is out of the valid range.'
        ids.q, ids.r = divmod(ids.value, ids.div)
    %}

    assert [range_check_ptr] = div - 1 - r;
    let range_check_ptr = range_check_ptr + 1;
    // assert_le(r, div - 1);

    assert value = q * div + r;
    return (q, r);
}

func get_felt_bitlength{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(x: felt) -> felt {
    alloc_locals;
    local bit_length;
    %{
        x = ids.x
        ids.bit_length = x.bit_length()
    %}

    // Next two commented lines are not necessary : will fail if pow2(bit_length) is too big, unknown cell.
    // let le = is_le(bit_length, 252);
    // assert le = 1;

    assert bitwise_ptr[0].x = x;
    let n = pow2(bit_length);
    assert bitwise_ptr[0].y = n - 1;
    tempvar word = bitwise_ptr[0].x_and_y;
    assert word = x;

    assert bitwise_ptr[1].x = x;

    let n = pow2(bit_length - 1);

    assert bitwise_ptr[1].y = n - 1;
    tempvar word = bitwise_ptr[1].x_and_y;
    assert word = x - n;

    let bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;
    return bit_length;
}

func word_reverse_endian_64{bitwise_ptr: BitwiseBuiltin*}(word: felt) -> (res: felt) {
    // A function to reverse the endianness of a 8 bytes (64 bits) integer.
    // The result will not make sense if word > 2^64.
    // The implementation is directly inspired by the function word_reverse_endian
    // from the common library starkware.cairo.common.uint256 with three steps instead of four.

    // Step 1.
    assert bitwise_ptr[0].x = word;
    assert bitwise_ptr[0].y = 0x00ff00ff00ff00ff00ff00ff00ff00ff;
    tempvar word = word + (2 ** 16 - 1) * bitwise_ptr[0].x_and_y;
    // Step 2.
    assert bitwise_ptr[1].x = word;
    assert bitwise_ptr[1].y = 0x00ffff0000ffff0000ffff0000ffff00;
    tempvar word = word + (2 ** 32 - 1) * bitwise_ptr[1].x_and_y;
    // Step 3.
    assert bitwise_ptr[2].x = word;
    assert bitwise_ptr[2].y = 0x00ffffffff00000000ffffffff000000;
    tempvar word = word + (2 ** 64 - 1) * bitwise_ptr[2].x_and_y;

    let bitwise_ptr = bitwise_ptr + 3 * BitwiseBuiltin.SIZE;
    return (res=word / 2 ** (8 + 16 + 32));
}

func word_reverse_endian_64_RC{range_check_ptr}(word: felt) -> felt {
    %{
        word = ids.word
        assert word < 2**64
        word_bytes=word.to_bytes(8, byteorder='big')
        for i in range(8):
            memory[ap+i] = word_bytes[i]
    %}
    ap += 8;

    let b0 = [ap - 8];
    let b1 = [ap - 7];
    let b2 = [ap - 6];
    let b3 = [ap - 5];
    let b4 = [ap - 4];
    let b5 = [ap - 3];
    let b6 = [ap - 2];
    let b7 = [ap - 1];

    assert [range_check_ptr] = b0;
    assert [range_check_ptr + 1] = b1;
    assert [range_check_ptr + 2] = b2;
    assert [range_check_ptr + 3] = b3;
    assert [range_check_ptr + 4] = b4;
    assert [range_check_ptr + 5] = b5;
    assert [range_check_ptr + 6] = b6;
    assert [range_check_ptr + 7] = b7;

    assert word = b0 * 256 ** 7 + b1 * 256 ** 6 + b2 * 256 ** 5 + b3 * 256 ** 4 + b4 * 256 ** 3 +
        b5 * 256 ** 2 + b6 * 256 + b7;

    tempvar range_check_ptr = range_check_ptr + 8;
    return b0 + b1 * 256 + b2 * 256 ** 2 + b3 * 256 ** 3 + b4 * 256 ** 4 + b5 * 256 ** 5 + b6 *
        256 ** 6 + b7 * 256 ** 7;
}

func word_reverse_endian_16_RC{range_check_ptr}(word: felt) -> felt {
    %{
        word = ids.word
        assert word < 2**16
        word_bytes=word.to_bytes(2, byteorder='big')
        for i in range(2):
            memory[ap+i] = word_bytes[i]
    %}
    ap += 2;

    let b0 = [ap - 2];
    let b1 = [ap - 1];

    assert [range_check_ptr] = b0;
    assert [range_check_ptr + 1] = b1;

    assert word = b0 * 256 + b1;

    tempvar range_check_ptr = range_check_ptr + 2;
    return b0 + b1 * 256;
}

func word_reverse_endian_24_RC{range_check_ptr}(word: felt) -> felt {
    %{
        word = ids.word
        assert word < 2**24
        word_bytes=word.to_bytes(3, byteorder='big')
        for i in range(3):
            memory[ap+i] = word_bytes[i]
    %}
    ap += 3;

    let b0 = [ap - 3];
    let b1 = [ap - 2];
    let b2 = [ap - 1];

    assert [range_check_ptr] = b0;
    assert [range_check_ptr + 1] = b1;
    assert [range_check_ptr + 2] = b2;

    assert word = b0 * 256 ** 2 + b1 * 256 + b2;

    tempvar range_check_ptr = range_check_ptr + 3;
    return b0 + b1 * 256 + b2 * 256 ** 2;
}

func word_reverse_endian_32_RC{range_check_ptr}(word: felt) -> felt {
    %{
        word = ids.word
        assert word < 2**32
        word_bytes=word.to_bytes(4, byteorder='big')
        for i in range(4):
            memory[ap+i] = word_bytes[i]
    %}
    ap += 4;

    let b0 = [ap - 4];
    let b1 = [ap - 3];
    let b2 = [ap - 2];
    let b3 = [ap - 1];

    assert [range_check_ptr] = b0;
    assert [range_check_ptr + 1] = b1;
    assert [range_check_ptr + 2] = b2;
    assert [range_check_ptr + 3] = b3;

    assert word = b0 * 256 ** 3 + b1 * 256 ** 2 + b2 * 256 + b3;

    tempvar range_check_ptr = range_check_ptr + 4;
    return b0 + b1 * 256 + b2 * 256 ** 2 + b3 * 256 ** 3;
}

func word_reverse_endian_40_RC{range_check_ptr}(word: felt) -> felt {
    %{
        word = ids.word
        assert word < 2**40
        word_bytes=word.to_bytes(5, byteorder='big')
        for i in range(5):
            memory[ap+i] = word_bytes[i]
    %}
    ap += 5;

    let b0 = [ap - 5];
    let b1 = [ap - 4];
    let b2 = [ap - 3];
    let b3 = [ap - 2];
    let b4 = [ap - 1];

    assert [range_check_ptr] = b0;
    assert [range_check_ptr + 1] = b1;
    assert [range_check_ptr + 2] = b2;
    assert [range_check_ptr + 3] = b3;
    assert [range_check_ptr + 4] = b4;

    assert word = b0 * 256 ** 4 + b1 * 256 ** 3 + b2 * 256 ** 2 + b3 * 256 + b4;

    tempvar range_check_ptr = range_check_ptr + 5;
    return b0 + b1 * 256 + b2 * 256 ** 2 + b3 * 256 ** 3 + b4 * 256 ** 4;
}

func word_reverse_endian_48_RC{range_check_ptr}(word: felt) -> felt {
    %{
        word = ids.word
        assert word < 2**48
        word_bytes=word.to_bytes(6, byteorder='big')
        for i in range(6):
            memory[ap+i] = word_bytes[i]
    %}
    ap += 6;

    let b0 = [ap - 6];
    let b1 = [ap - 5];
    let b2 = [ap - 4];
    let b3 = [ap - 3];
    let b4 = [ap - 2];
    let b5 = [ap - 1];

    assert [range_check_ptr] = b0;
    assert [range_check_ptr + 1] = b1;
    assert [range_check_ptr + 2] = b2;
    assert [range_check_ptr + 3] = b3;
    assert [range_check_ptr + 4] = b4;
    assert [range_check_ptr + 5] = b5;

    assert word = b0 * 256 ** 5 + b1 * 256 ** 4 + b2 * 256 ** 3 + b3 * 256 ** 2 + b4 * 256 + b5;

    tempvar range_check_ptr = range_check_ptr + 6;
    return b0 + b1 * 256 + b2 * 256 ** 2 + b3 * 256 ** 3 + b4 * 256 ** 4 + b5 * 256 ** 5;
}

func word_reverse_endian_56_RC{range_check_ptr}(word: felt) -> felt {
    %{
        word = ids.word
        assert word < 2**56
        word_bytes=word.to_bytes(7, byteorder='big')
        for i in range(7):
            memory[ap+i] = word_bytes[i]
    %}
    ap += 7;

    let b0 = [ap - 7];
    let b1 = [ap - 6];
    let b2 = [ap - 5];
    let b3 = [ap - 4];
    let b4 = [ap - 3];
    let b5 = [ap - 2];
    let b6 = [ap - 1];

    assert [range_check_ptr] = b0;
    assert [range_check_ptr + 1] = b1;
    assert [range_check_ptr + 2] = b2;
    assert [range_check_ptr + 3] = b3;
    assert [range_check_ptr + 4] = b4;
    assert [range_check_ptr + 5] = b5;
    assert [range_check_ptr + 6] = b6;

    assert word = b0 * 256 ** 6 + b1 * 256 ** 5 + b2 * 256 ** 4 + b3 * 256 ** 3 + b4 * 256 ** 2 +
        b5 * 256 + b6;

    tempvar range_check_ptr = range_check_ptr + 7;
    return b0 + b1 * 256 + b2 * 256 ** 2 + b3 * 256 ** 3 + b4 * 256 ** 4 + b5 * 256 ** 5 + b6 *
        256 ** 6;
}

func word_reverse_endian_32{bitwise_ptr: BitwiseBuiltin*}(word: felt) -> (res: felt) {
    // A function to reverse the endianness of a 4 bytes (32 bits) integer.
    // The result will not make sense if word > 2^32.
    // The implementation is directly inspired by the function word_reverse_endian
    // Step 1.
    assert bitwise_ptr[0].x = word;
    assert bitwise_ptr[0].y = 0x00ff00ff00ff00ff00ff00ff00ff00ff;
    tempvar word = word + (2 ** 16 - 1) * bitwise_ptr[0].x_and_y;
    // Step 2.
    assert bitwise_ptr[1].x = word;
    assert bitwise_ptr[1].y = 0x00ffff0000ffff0000ffff0000ffff00;
    tempvar word = word + (2 ** 32 - 1) * bitwise_ptr[1].x_and_y;

    let bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;
    return (res=word / 2 ** (8 + 16));
}

// Utility to get 2^i from i = 0 to 127.
// If i>127, fails.
func pow2alloc127() -> (array: felt*) {
    let (data_address) = get_label_location(data);
    return (data_address,);

    data:
    dw 0x1;
    dw 0x2;
    dw 0x4;
    dw 0x8;
    dw 0x10;
    dw 0x20;
    dw 0x40;
    dw 0x80;
    dw 0x100;
    dw 0x200;
    dw 0x400;
    dw 0x800;
    dw 0x1000;
    dw 0x2000;
    dw 0x4000;
    dw 0x8000;
    dw 0x10000;
    dw 0x20000;
    dw 0x40000;
    dw 0x80000;
    dw 0x100000;
    dw 0x200000;
    dw 0x400000;
    dw 0x800000;
    dw 0x1000000;
    dw 0x2000000;
    dw 0x4000000;
    dw 0x8000000;
    dw 0x10000000;
    dw 0x20000000;
    dw 0x40000000;
    dw 0x80000000;
    dw 0x100000000;
    dw 0x200000000;
    dw 0x400000000;
    dw 0x800000000;
    dw 0x1000000000;
    dw 0x2000000000;
    dw 0x4000000000;
    dw 0x8000000000;
    dw 0x10000000000;
    dw 0x20000000000;
    dw 0x40000000000;
    dw 0x80000000000;
    dw 0x100000000000;
    dw 0x200000000000;
    dw 0x400000000000;
    dw 0x800000000000;
    dw 0x1000000000000;
    dw 0x2000000000000;
    dw 0x4000000000000;
    dw 0x8000000000000;
    dw 0x10000000000000;
    dw 0x20000000000000;
    dw 0x40000000000000;
    dw 0x80000000000000;
    dw 0x100000000000000;
    dw 0x200000000000000;
    dw 0x400000000000000;
    dw 0x800000000000000;
    dw 0x1000000000000000;
    dw 0x2000000000000000;
    dw 0x4000000000000000;
    dw 0x8000000000000000;
    dw 0x10000000000000000;
    dw 0x20000000000000000;
    dw 0x40000000000000000;
    dw 0x80000000000000000;
    dw 0x100000000000000000;
    dw 0x200000000000000000;
    dw 0x400000000000000000;
    dw 0x800000000000000000;
    dw 0x1000000000000000000;
    dw 0x2000000000000000000;
    dw 0x4000000000000000000;
    dw 0x8000000000000000000;
    dw 0x10000000000000000000;
    dw 0x20000000000000000000;
    dw 0x40000000000000000000;
    dw 0x80000000000000000000;
    dw 0x100000000000000000000;
    dw 0x200000000000000000000;
    dw 0x400000000000000000000;
    dw 0x800000000000000000000;
    dw 0x1000000000000000000000;
    dw 0x2000000000000000000000;
    dw 0x4000000000000000000000;
    dw 0x8000000000000000000000;
    dw 0x10000000000000000000000;
    dw 0x20000000000000000000000;
    dw 0x40000000000000000000000;
    dw 0x80000000000000000000000;
    dw 0x100000000000000000000000;
    dw 0x200000000000000000000000;
    dw 0x400000000000000000000000;
    dw 0x800000000000000000000000;
    dw 0x1000000000000000000000000;
    dw 0x2000000000000000000000000;
    dw 0x4000000000000000000000000;
    dw 0x8000000000000000000000000;
    dw 0x10000000000000000000000000;
    dw 0x20000000000000000000000000;
    dw 0x40000000000000000000000000;
    dw 0x80000000000000000000000000;
    dw 0x100000000000000000000000000;
    dw 0x200000000000000000000000000;
    dw 0x400000000000000000000000000;
    dw 0x800000000000000000000000000;
    dw 0x1000000000000000000000000000;
    dw 0x2000000000000000000000000000;
    dw 0x4000000000000000000000000000;
    dw 0x8000000000000000000000000000;
    dw 0x10000000000000000000000000000;
    dw 0x20000000000000000000000000000;
    dw 0x40000000000000000000000000000;
    dw 0x80000000000000000000000000000;
    dw 0x100000000000000000000000000000;
    dw 0x200000000000000000000000000000;
    dw 0x400000000000000000000000000000;
    dw 0x800000000000000000000000000000;
    dw 0x1000000000000000000000000000000;
    dw 0x2000000000000000000000000000000;
    dw 0x4000000000000000000000000000000;
    dw 0x8000000000000000000000000000000;
    dw 0x10000000000000000000000000000000;
    dw 0x20000000000000000000000000000000;
    dw 0x40000000000000000000000000000000;
    dw 0x80000000000000000000000000000000;
}

// Utility to get 2^i when i is a cairo variable.
func pow2(i) -> felt {
    let (data_address) = get_label_location(data);
    return [data_address + i];

    data:
    dw 0x1;
    dw 0x2;
    dw 0x4;
    dw 0x8;
    dw 0x10;
    dw 0x20;
    dw 0x40;
    dw 0x80;
    dw 0x100;
    dw 0x200;
    dw 0x400;
    dw 0x800;
    dw 0x1000;
    dw 0x2000;
    dw 0x4000;
    dw 0x8000;
    dw 0x10000;
    dw 0x20000;
    dw 0x40000;
    dw 0x80000;
    dw 0x100000;
    dw 0x200000;
    dw 0x400000;
    dw 0x800000;
    dw 0x1000000;
    dw 0x2000000;
    dw 0x4000000;
    dw 0x8000000;
    dw 0x10000000;
    dw 0x20000000;
    dw 0x40000000;
    dw 0x80000000;
    dw 0x100000000;
    dw 0x200000000;
    dw 0x400000000;
    dw 0x800000000;
    dw 0x1000000000;
    dw 0x2000000000;
    dw 0x4000000000;
    dw 0x8000000000;
    dw 0x10000000000;
    dw 0x20000000000;
    dw 0x40000000000;
    dw 0x80000000000;
    dw 0x100000000000;
    dw 0x200000000000;
    dw 0x400000000000;
    dw 0x800000000000;
    dw 0x1000000000000;
    dw 0x2000000000000;
    dw 0x4000000000000;
    dw 0x8000000000000;
    dw 0x10000000000000;
    dw 0x20000000000000;
    dw 0x40000000000000;
    dw 0x80000000000000;
    dw 0x100000000000000;
    dw 0x200000000000000;
    dw 0x400000000000000;
    dw 0x800000000000000;
    dw 0x1000000000000000;
    dw 0x2000000000000000;
    dw 0x4000000000000000;
    dw 0x8000000000000000;
    dw 0x10000000000000000;
    dw 0x20000000000000000;
    dw 0x40000000000000000;
    dw 0x80000000000000000;
    dw 0x100000000000000000;
    dw 0x200000000000000000;
    dw 0x400000000000000000;
    dw 0x800000000000000000;
    dw 0x1000000000000000000;
    dw 0x2000000000000000000;
    dw 0x4000000000000000000;
    dw 0x8000000000000000000;
    dw 0x10000000000000000000;
    dw 0x20000000000000000000;
    dw 0x40000000000000000000;
    dw 0x80000000000000000000;
    dw 0x100000000000000000000;
    dw 0x200000000000000000000;
    dw 0x400000000000000000000;
    dw 0x800000000000000000000;
    dw 0x1000000000000000000000;
    dw 0x2000000000000000000000;
    dw 0x4000000000000000000000;
    dw 0x8000000000000000000000;
    dw 0x10000000000000000000000;
    dw 0x20000000000000000000000;
    dw 0x40000000000000000000000;
    dw 0x80000000000000000000000;
    dw 0x100000000000000000000000;
    dw 0x200000000000000000000000;
    dw 0x400000000000000000000000;
    dw 0x800000000000000000000000;
    dw 0x1000000000000000000000000;
    dw 0x2000000000000000000000000;
    dw 0x4000000000000000000000000;
    dw 0x8000000000000000000000000;
    dw 0x10000000000000000000000000;
    dw 0x20000000000000000000000000;
    dw 0x40000000000000000000000000;
    dw 0x80000000000000000000000000;
    dw 0x100000000000000000000000000;
    dw 0x200000000000000000000000000;
    dw 0x400000000000000000000000000;
    dw 0x800000000000000000000000000;
    dw 0x1000000000000000000000000000;
    dw 0x2000000000000000000000000000;
    dw 0x4000000000000000000000000000;
    dw 0x8000000000000000000000000000;
    dw 0x10000000000000000000000000000;
    dw 0x20000000000000000000000000000;
    dw 0x40000000000000000000000000000;
    dw 0x80000000000000000000000000000;
    dw 0x100000000000000000000000000000;
    dw 0x200000000000000000000000000000;
    dw 0x400000000000000000000000000000;
    dw 0x800000000000000000000000000000;
    dw 0x1000000000000000000000000000000;
    dw 0x2000000000000000000000000000000;
    dw 0x4000000000000000000000000000000;
    dw 0x8000000000000000000000000000000;
    dw 0x10000000000000000000000000000000;
    dw 0x20000000000000000000000000000000;
    dw 0x40000000000000000000000000000000;
    dw 0x80000000000000000000000000000000;
    dw 0x100000000000000000000000000000000;
    dw 0x200000000000000000000000000000000;
    dw 0x400000000000000000000000000000000;
    dw 0x800000000000000000000000000000000;
    dw 0x1000000000000000000000000000000000;
    dw 0x2000000000000000000000000000000000;
    dw 0x4000000000000000000000000000000000;
    dw 0x8000000000000000000000000000000000;
    dw 0x10000000000000000000000000000000000;
    dw 0x20000000000000000000000000000000000;
    dw 0x40000000000000000000000000000000000;
    dw 0x80000000000000000000000000000000000;
    dw 0x100000000000000000000000000000000000;
    dw 0x200000000000000000000000000000000000;
    dw 0x400000000000000000000000000000000000;
    dw 0x800000000000000000000000000000000000;
    dw 0x1000000000000000000000000000000000000;
    dw 0x2000000000000000000000000000000000000;
    dw 0x4000000000000000000000000000000000000;
    dw 0x8000000000000000000000000000000000000;
    dw 0x10000000000000000000000000000000000000;
    dw 0x20000000000000000000000000000000000000;
    dw 0x40000000000000000000000000000000000000;
    dw 0x80000000000000000000000000000000000000;
    dw 0x100000000000000000000000000000000000000;
    dw 0x200000000000000000000000000000000000000;
    dw 0x400000000000000000000000000000000000000;
    dw 0x800000000000000000000000000000000000000;
    dw 0x1000000000000000000000000000000000000000;
    dw 0x2000000000000000000000000000000000000000;
    dw 0x4000000000000000000000000000000000000000;
    dw 0x8000000000000000000000000000000000000000;
    dw 0x10000000000000000000000000000000000000000;
    dw 0x20000000000000000000000000000000000000000;
    dw 0x40000000000000000000000000000000000000000;
    dw 0x80000000000000000000000000000000000000000;
    dw 0x100000000000000000000000000000000000000000;
    dw 0x200000000000000000000000000000000000000000;
    dw 0x400000000000000000000000000000000000000000;
    dw 0x800000000000000000000000000000000000000000;
    dw 0x1000000000000000000000000000000000000000000;
    dw 0x2000000000000000000000000000000000000000000;
    dw 0x4000000000000000000000000000000000000000000;
    dw 0x8000000000000000000000000000000000000000000;
    dw 0x10000000000000000000000000000000000000000000;
    dw 0x20000000000000000000000000000000000000000000;
    dw 0x40000000000000000000000000000000000000000000;
    dw 0x80000000000000000000000000000000000000000000;
    dw 0x100000000000000000000000000000000000000000000;
    dw 0x200000000000000000000000000000000000000000000;
    dw 0x400000000000000000000000000000000000000000000;
    dw 0x800000000000000000000000000000000000000000000;
    dw 0x1000000000000000000000000000000000000000000000;
    dw 0x2000000000000000000000000000000000000000000000;
    dw 0x4000000000000000000000000000000000000000000000;
    dw 0x8000000000000000000000000000000000000000000000;
    dw 0x10000000000000000000000000000000000000000000000;
    dw 0x20000000000000000000000000000000000000000000000;
    dw 0x40000000000000000000000000000000000000000000000;
    dw 0x80000000000000000000000000000000000000000000000;
    dw 0x100000000000000000000000000000000000000000000000;
    dw 0x200000000000000000000000000000000000000000000000;
    dw 0x400000000000000000000000000000000000000000000000;
    dw 0x800000000000000000000000000000000000000000000000;
    dw 0x1000000000000000000000000000000000000000000000000;
    dw 0x2000000000000000000000000000000000000000000000000;
    dw 0x4000000000000000000000000000000000000000000000000;
    dw 0x8000000000000000000000000000000000000000000000000;
    dw 0x10000000000000000000000000000000000000000000000000;
    dw 0x20000000000000000000000000000000000000000000000000;
    dw 0x40000000000000000000000000000000000000000000000000;
    dw 0x80000000000000000000000000000000000000000000000000;
    dw 0x100000000000000000000000000000000000000000000000000;
    dw 0x200000000000000000000000000000000000000000000000000;
    dw 0x400000000000000000000000000000000000000000000000000;
    dw 0x800000000000000000000000000000000000000000000000000;
    dw 0x1000000000000000000000000000000000000000000000000000;
    dw 0x2000000000000000000000000000000000000000000000000000;
    dw 0x4000000000000000000000000000000000000000000000000000;
    dw 0x8000000000000000000000000000000000000000000000000000;
    dw 0x10000000000000000000000000000000000000000000000000000;
    dw 0x20000000000000000000000000000000000000000000000000000;
    dw 0x40000000000000000000000000000000000000000000000000000;
    dw 0x80000000000000000000000000000000000000000000000000000;
    dw 0x100000000000000000000000000000000000000000000000000000;
    dw 0x200000000000000000000000000000000000000000000000000000;
    dw 0x400000000000000000000000000000000000000000000000000000;
    dw 0x800000000000000000000000000000000000000000000000000000;
    dw 0x1000000000000000000000000000000000000000000000000000000;
    dw 0x2000000000000000000000000000000000000000000000000000000;
    dw 0x4000000000000000000000000000000000000000000000000000000;
    dw 0x8000000000000000000000000000000000000000000000000000000;
    dw 0x10000000000000000000000000000000000000000000000000000000;
    dw 0x20000000000000000000000000000000000000000000000000000000;
    dw 0x40000000000000000000000000000000000000000000000000000000;
    dw 0x80000000000000000000000000000000000000000000000000000000;
    dw 0x100000000000000000000000000000000000000000000000000000000;
    dw 0x200000000000000000000000000000000000000000000000000000000;
    dw 0x400000000000000000000000000000000000000000000000000000000;
    dw 0x800000000000000000000000000000000000000000000000000000000;
    dw 0x1000000000000000000000000000000000000000000000000000000000;
    dw 0x2000000000000000000000000000000000000000000000000000000000;
    dw 0x4000000000000000000000000000000000000000000000000000000000;
    dw 0x8000000000000000000000000000000000000000000000000000000000;
    dw 0x10000000000000000000000000000000000000000000000000000000000;
    dw 0x20000000000000000000000000000000000000000000000000000000000;
    dw 0x40000000000000000000000000000000000000000000000000000000000;
    dw 0x80000000000000000000000000000000000000000000000000000000000;
    dw 0x100000000000000000000000000000000000000000000000000000000000;
    dw 0x200000000000000000000000000000000000000000000000000000000000;
    dw 0x400000000000000000000000000000000000000000000000000000000000;
    dw 0x800000000000000000000000000000000000000000000000000000000000;
    dw 0x1000000000000000000000000000000000000000000000000000000000000;
    dw 0x2000000000000000000000000000000000000000000000000000000000000;
    dw 0x4000000000000000000000000000000000000000000000000000000000000;
    dw 0x8000000000000000000000000000000000000000000000000000000000000;
    dw 0x10000000000000000000000000000000000000000000000000000000000000;
    dw 0x20000000000000000000000000000000000000000000000000000000000000;
    dw 0x40000000000000000000000000000000000000000000000000000000000000;
    dw 0x80000000000000000000000000000000000000000000000000000000000000;
    dw 0x100000000000000000000000000000000000000000000000000000000000000;
    dw 0x200000000000000000000000000000000000000000000000000000000000000;
    dw 0x400000000000000000000000000000000000000000000000000000000000000;
}

func print_debug() {
    alloc_locals;
    %{
        def bin_c(u):
            b=bin(u)
            f = b[0:10] + ' ' + b[10:19] + '...' + b[-16:-8] + ' ' + b[-8:]
            return f
        def bin_64(u):
            b=bin(u)
            little = '0b'+b[2:][::-1]
            f='0b'+' '.join([b[2:][i:i+64] for i in range(0, len(b[2:]), 64)])
            return f
        def bin_8(u):
            b=bin(u)
            little = '0b'+b[2:][::-1]
            f="0b"+' '.join([little[2:][i:i+8] for i in range(0, len(little[2:]), 8)])
            return f
        def print_u256_info(u, un):
            u = u.low + (u.high << 128) 
            print(f" {un}_{u.bit_length()}bits = {bin_c(u)}")
            print(f" {un} = {hex(u)}")
            print(f" {un} = {int.to_bytes(u, 32, 'big')}")
        def print_felt_info(u, un, n_bytes):
            print(f" {un}_{u.bit_length()}bits = {bin_8(u)}")
            print(f" {un} = {u}")
            print(f" {un} = {int.to_bytes(u, n_bytes, 'big')}")
    %}
    return ();
}
