%builtins range_check

from src.libs.bn254.fq import fq, BASE, BASE_MIN_1, DEGREE, N_LIMBS, P0, P1, P2
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from starkware.cairo.common.cairo_secp.bigint import BigInt3
from starkware.cairo.common.alloc import alloc

func main{range_check_ptr}() {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();

    local nine: BigInt3 = BigInt3(9, 0, 0);
    local eleven: BigInt3 = BigInt3(11, 0, 0);

    let x = hash_two(&nine, &eleven);

    %{
        def print_bigint3(x, name):
            print(f"{name} = {x.d0 + x.d1*2**86 + x.d2*2**172}")

        print_bigint3(ids.nine, "x")
        print_bigint3(ids.x, "x")
    %}

    return ();
}

struct PoseidonState {
    s0: BigInt3*,
    s1: BigInt3*,
    s2: BigInt3*,
}

const r_p = 83;
const r_f = 8;
const r_f_div_2 = 4;

func hash_two{range_check_ptr}(x: BigInt3*, y: BigInt3*) -> BigInt3* {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();

    local two: BigInt3 = BigInt3(2, 0, 0);
    local state: PoseidonState = PoseidonState(s0=x, s1=y, s2=&two);

    let round_constants: BigInt3* = get_round_constants();
    // Hades Permutation

    with round_constants {
        let half_full: PoseidonState* = hades_round_full(&state, 0, 0);
        let partial: PoseidonState* = hades_round_partial(half_full, r_f_div_2, 0);
        let final_state: PoseidonState* = hades_round_full(partial, r_f_div_2 + r_p, 0);
    }

    let res = final_state.s0;
    return res;
}

func hades_round_full{range_check_ptr, round_constants: BigInt3*}(
    state: PoseidonState*, round_idx: felt, index: felt
) -> PoseidonState* {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    %{ print("round index, index : ", ids.round_idx, ids.index) %}
    if (index == r_f_div_2) {
        return state;
    }

    // 1. Add round constants

    let state0 = fq.add_rc(state.s0, round_idx * 3);
    let state1 = fq.add_rc(state.s1, round_idx * 3 + 1);
    let state2 = fq.add_rc(state.s2, round_idx * 3 + 2);

    // 2. Apply sbox
    let square0 = fq.square(state0);
    let r0 = fq.mul(square0, state0);

    let square1 = fq.square(state1);
    let r1 = fq.mul(square1, state1);

    let square2 = fq.square(state2);
    let r2 = fq.mul(square2, state2);

    // 3. Multiply by MDS matrix

    // MixLayer using SmallMds =
    // [3, 1, 1]    [r0]    [3* r0 + r1 + r2 ]
    // [1, -1, 1]  *[r1]  = [r0 - r1 + r2    ]
    // [1, 1, -2]   [r2]    [r0 + r1 - 2 * r2]

    local mds_mul0: BigInt3;
    local mds_mul1: BigInt3;
    local mds_mul2: BigInt3;
    local q0: felt;
    local q1: felt;
    local q2: felt;
    local mds_0_c0: felt;
    local mds_0_c1: felt;
    local mds_1_c0: felt;
    local mds_1_c1: felt;
    local mds_2_c0: felt;
    local mds_2_c1: felt;
    local mds_0_flag0: felt;
    local mds_0_flag1: felt;
    local mds_1_flag0: felt;
    local mds_1_flag1: felt;
    local mds_2_flag0: felt;
    local mds_2_flag1: felt;

    %{
        r0,r1,r2,p, r0_limbs, r1_limbs, r2_limbs, p_limbs = 0,0,0,0,ids.N_LIMBS*[0],ids.N_LIMBS*[0],ids.N_LIMBS*[0],ids.N_LIMBS*[0]

        def split(x, degree=ids.DEGREE, base=ids.BASE):
            coeffs = []
            for n in range(degree, 0, -1):
                q, r = divmod(x, base ** n)
                coeffs.append(q)
                x = r
            coeffs.append(x)
            return coeffs[::-1]
        def abs_poly(x:list):
            result = [0] * len(x)
            for i in range(len(x)):
                result[i] = abs(x[i])
            return result

        def reduce_zero_poly(x:list):
            x = x.copy()
            carries = [0] * (len(x)-1)
            for i in range(0, len(x)-1):
                carries[i] = x[i] // ids.BASE
                x[i] = x[i] % ids.BASE
                assert x[i] == 0
                x[i+1] += carries[i]
            assert x[-1] == 0
            return x, carries
        for i in range(ids.N_LIMBS):
            r0+=as_int(getattr(ids.r0, 'd'+str(i)),PRIME) * ids.BASE**i
            r1+=as_int(getattr(ids.r1, 'd'+str(i)),PRIME) * ids.BASE**i
            r2+=as_int(getattr(ids.r2, 'd'+str(i)),PRIME) * ids.BASE**i
            p+=getattr(ids, 'P'+str(i)) * ids.BASE**i
            r0_limbs[i]=as_int(getattr(ids.r0, 'd'+str(i)),PRIME)
            r1_limbs[i]=as_int(getattr(ids.r1, 'd'+str(i)),PRIME)
            r2_limbs[i]=as_int(getattr(ids.r2, 'd'+str(i)),PRIME)
            p_limbs[i]=getattr(ids, 'P'+str(i))

        mds_0 = (3 * r0 + r1 + r2)
        mds_1 = (r0 - r1 + r2)
        mds_2 = (r0 + r1 - 2 * r2)
        q = [mds_0//p, mds_1//p, mds_2//p]
        assert abs(q[0]) < ids.BASE
        assert abs(q[1]) < ids.BASE
        assert abs(q[2]) < ids.BASE
        print('q', q)
        mds_0, mds_1, mds_2 = mds_0%p, mds_1%p, mds_2%p

        diff_0, diff_1, diff_2=ids.N_LIMBS*[0], ids.N_LIMBS*[0], ids.N_LIMBS*[0]
        # carries_0, carries_1, carries_2=ids.DEGREE*[0], ids.DEGREE*[0], ids.DEGREE*[0]

        mds_0_s, mds_1_s, mds_2_s = split(mds_0%p), split(mds_1%p), split(mds_2%p)
        for i in range(3):
            diff_0[i] = 3*r0_limbs[i] + r1_limbs[i] + r2_limbs[i] - q[0]*p_limbs[i] - mds_0_s[i]
            diff_1[i] = r0_limbs[i] - r1_limbs[i] + r2_limbs[i] - q[1]*p_limbs[i] - mds_1_s[i]
            diff_2[i] = r0_limbs[i] + r1_limbs[i] - 2*r2_limbs[i] - q[2]*p_limbs[i] - mds_2_s[i]
        print('diff_0', diff_0)
        print('diff_1', diff_1)
        print('diff_2', diff_2)
        _, carries_0 = reduce_zero_poly(diff_0)
        _, carries_1 = reduce_zero_poly(diff_1)
        _, carries_2 = reduce_zero_poly(diff_2)
        carries_0 = abs_poly(carries_0)
        carries_1 = abs_poly(carries_1)
        carries_2 = abs_poly(carries_2)
        for i in range(2):
            setattr(ids, 'mds_0_c'+str(i), carries_0[i])
            setattr(ids, 'mds_1_c'+str(i), carries_1[i])
            setattr(ids, 'mds_2_c'+str(i), carries_2[i])
        for i in range(3):
            setattr(ids, 'q'+str(i), q[i])
        for i in range(ids.N_LIMBS):
            setattr(ids.mds_mul0, 'd'+str(i), mds_0_s[i])
            setattr(ids.mds_mul1, 'd'+str(i), mds_1_s[i])
            setattr(ids.mds_mul2, 'd'+str(i), mds_2_s[i])
        for i in range(2):
            setattr(ids,'mds_0_flag'+str(i), 1 if diff_0[i] >= 0 else 0)
            setattr(ids,'mds_1_flag'+str(i), 1 if diff_1[i] >= 0 else 0)
            setattr(ids,'mds_2_flag'+str(i), 1 if diff_2[i] >= 0 else 0)
    %}

    assert [range_check_ptr] = 4 - q0;
    assert [range_check_ptr + 1] = 2 - q1;
    assert [range_check_ptr + 2] = 2 - q2;
    assert [range_check_ptr + 3] = BASE_MIN_1 - mds_mul0.d0;
    assert [range_check_ptr + 4] = BASE_MIN_1 - mds_mul0.d1;
    assert [range_check_ptr + 5] = P2 - mds_mul0.d2;
    assert [range_check_ptr + 6] = BASE_MIN_1 - mds_mul1.d0;
    assert [range_check_ptr + 7] = BASE_MIN_1 - mds_mul1.d1;
    assert [range_check_ptr + 8] = P2 - mds_mul1.d2;
    assert [range_check_ptr + 9] = BASE_MIN_1 - mds_mul2.d0;
    assert [range_check_ptr + 10] = BASE_MIN_1 - mds_mul2.d1;
    assert [range_check_ptr + 11] = P2 - mds_mul2.d2;
    assert [range_check_ptr + 12] = mds_0_c0;
    assert [range_check_ptr + 13] = mds_0_c1;
    assert [range_check_ptr + 14] = mds_1_c0;
    assert [range_check_ptr + 15] = mds_1_c1;
    assert [range_check_ptr + 16] = mds_2_c0;
    assert [range_check_ptr + 17] = mds_2_c1;

    tempvar mds_0_d0_diff = 3 * r0.d0 + r1.d0 + r2.d0 - q0 * P0 - mds_mul0.d0;
    tempvar mds_0_d1_diff = 3 * r0.d1 + r1.d1 + r2.d1 - q0 * P1 - mds_mul0.d1;
    tempvar mds_0_d2_diff = 3 * r0.d2 + r1.d2 + r2.d2 - q0 * P2 - mds_mul0.d2;
    tempvar mds_1_d0_diff = r0.d0 - r1.d0 + r2.d0 - q1 * P0 - mds_mul1.d0;
    tempvar mds_1_d1_diff = r0.d1 - r1.d1 + r2.d1 - q1 * P1 - mds_mul1.d1;
    tempvar mds_1_d2_diff = r0.d2 - r1.d2 + r2.d2 - q1 * P2 - mds_mul1.d2;
    tempvar mds_2_d0_diff = r0.d0 + r1.d0 - 2 * r2.d0 - q2 * P0 - mds_mul2.d0;
    tempvar mds_2_d1_diff = r0.d1 + r1.d1 - 2 * r2.d1 - q2 * P1 - mds_mul2.d1;
    tempvar mds_2_d2_diff = r0.d2 + r1.d2 - 2 * r2.d2 - q2 * P2 - mds_mul2.d2;

    local mds_0_carry0;
    local mds_0_carry1;
    local mds_1_carry0;
    local mds_1_carry1;
    local mds_2_carry0;
    local mds_2_carry1;

    if (mds_0_flag0 != 0) {
        assert mds_0_carry0 = mds_0_c0;
        assert mds_0_d0_diff = mds_0_carry0 * BASE;
    } else {
        assert mds_0_carry0 = (-1) * mds_0_c0;
        assert mds_0_d0_diff = mds_0_carry0 * BASE;
    }
    if (mds_0_flag1 != 0) {
        assert mds_0_carry1 = mds_0_c1;
        assert mds_0_d1_diff + mds_0_carry0 = mds_0_carry1 * BASE;
    } else {
        assert mds_0_carry1 = (-1) * mds_0_c1;
        assert mds_0_d1_diff + mds_0_carry0 = mds_0_carry1 * BASE;
    }
    if (mds_1_flag0 != 0) {
        assert mds_1_carry0 = mds_1_c0;
        assert mds_1_d0_diff = mds_1_carry0 * BASE;
    } else {
        assert mds_1_carry0 = (-1) * mds_1_c0;
        assert mds_1_d0_diff = mds_1_carry0 * BASE;
    }
    if (mds_1_flag1 != 0) {
        assert mds_1_carry1 = mds_1_c1;
        assert mds_1_d1_diff + mds_1_carry0 = mds_1_carry1 * BASE;
    } else {
        assert mds_1_carry1 = (-1) * mds_1_c1;
        assert mds_1_d1_diff + mds_1_carry0 = mds_1_carry1 * BASE;
    }
    if (mds_2_flag0 != 0) {
        assert mds_2_carry0 = mds_2_c0;
        assert mds_2_d0_diff = mds_2_carry0 * BASE;
    } else {
        assert mds_2_carry0 = (-1) * mds_2_c0;
        assert mds_2_d0_diff = mds_2_carry0 * BASE;
    }
    if (mds_2_flag1 != 0) {
        assert mds_2_carry1 = mds_2_c1;
        assert mds_2_d1_diff + mds_2_carry0 = mds_2_carry1 * BASE;
    } else {
        assert mds_2_carry1 = (-1) * mds_2_c1;
        assert mds_2_d1_diff + mds_2_carry0 = mds_2_carry1 * BASE;
    }

    assert mds_0_d2_diff + mds_0_carry1 = 0;
    assert mds_1_d2_diff + mds_1_carry1 = 0;
    assert mds_2_d2_diff + mds_2_carry1 = 0;

    local mds_mul_state: PoseidonState = PoseidonState(s0=&mds_mul0, s1=&mds_mul1, s2=&mds_mul2);
    tempvar range_check_ptr = range_check_ptr + 18;
    return hades_round_full(&mds_mul_state, round_idx + 1, index + 1);
}

func hades_round_partial{range_check_ptr, round_constants: BigInt3*}(
    state: PoseidonState*, round_idx: felt, index: felt
) -> PoseidonState* {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    %{ print("round index, index : ", ids.round_idx, ids.index) %}

    if (index == r_p) {
        return state;
    }

    // 1. Add round constant

    let r0 = fq.add_rc(state.s0, round_idx * 3);
    let r1 = fq.add_rc(state.s1, round_idx * 3 + 1);
    let state2 = fq.add_rc(state.s2, round_idx * 3 + 2);

    // 2. Apply sbox to last element
    let square2 = fq.square(state2);
    let r2 = fq.mul(square2, state2);

    // 3. Multiply by MDS matrix
    // MixLayer using SmallMds =
    // [3, 1, 1]    [r0]    [3* r0 + r1 + r2 ]
    // [1, -1, 1]  *[r1]  = [r0 - r1 + r2    ]
    // [1, 1, -2]   [r2]    [r0 + r1 - 2 * r2]
    local mds_mul0: BigInt3;
    local mds_mul1: BigInt3;
    local mds_mul2: BigInt3;
    local q0: felt;
    local q1: felt;
    local q2: felt;
    local mds_0_c0: felt;
    local mds_0_c1: felt;
    local mds_1_c0: felt;
    local mds_1_c1: felt;
    local mds_2_c0: felt;
    local mds_2_c1: felt;
    local mds_0_flag0: felt;
    local mds_0_flag1: felt;
    local mds_1_flag0: felt;
    local mds_1_flag1: felt;
    local mds_2_flag0: felt;
    local mds_2_flag1: felt;

    %{
        r0,r1,r2,p, r0_limbs, r1_limbs, r2_limbs, p_limbs = 0,0,0,0,ids.N_LIMBS*[0],ids.N_LIMBS*[0],ids.N_LIMBS*[0],ids.N_LIMBS*[0] 

        def split(x, degree=ids.DEGREE, base=ids.BASE):
            coeffs = []
            for n in range(degree, 0, -1):
                q, r = divmod(x, base ** n)
                coeffs.append(q)
                x = r
            coeffs.append(x)
            return coeffs[::-1]
        def abs_poly(x:list):
            result = [0] * len(x)
            for i in range(len(x)):
                result[i] = abs(x[i])
            return result

        def reduce_zero_poly(x:list):
            x = x.copy()
            carries = [0] * (len(x)-1)
            for i in range(0, len(x)-1):
                carries[i] = x[i] // ids.BASE
                x[i] = x[i] % ids.BASE
                assert x[i] == 0
                x[i+1] += carries[i]
            assert x[-1] == 0
            return x, carries
        for i in range(ids.N_LIMBS):
            r0+=as_int(getattr(ids.r0, 'd'+str(i)),PRIME) * ids.BASE**i
            r1+=as_int(getattr(ids.r1, 'd'+str(i)),PRIME) * ids.BASE**i
            r2+=as_int(getattr(ids.r2, 'd'+str(i)),PRIME) * ids.BASE**i
            p+=getattr(ids, 'P'+str(i)) * ids.BASE**i
            r0_limbs[i]=as_int(getattr(ids.r0, 'd'+str(i)),PRIME)
            r1_limbs[i]=as_int(getattr(ids.r1, 'd'+str(i)),PRIME)
            r2_limbs[i]=as_int(getattr(ids.r2, 'd'+str(i)),PRIME)
            p_limbs[i]=getattr(ids, 'P'+str(i))

        mds_0 = (3 * r0 + r1 + r2)
        mds_1 = (r0 - r1 + r2)
        mds_2 = (r0 + r1 - 2 * r2)
        q = [mds_0//p, mds_1//p, mds_2//p]
        assert abs(q[0]) < ids.BASE
        assert abs(q[1]) < ids.BASE
        assert abs(q[2]) < ids.BASE
        #print('q', q)
        mds_0, mds_1, mds_2 = mds_0%p, mds_1%p, mds_2%p

        diff_0, diff_1, diff_2=ids.N_LIMBS*[0], ids.N_LIMBS*[0], ids.N_LIMBS*[0]
        # carries_0, carries_1, carries_2=ids.DEGREE*[0], ids.DEGREE*[0], ids.DEGREE*[0]

        mds_0_s, mds_1_s, mds_2_s = split(mds_0%p), split(mds_1%p), split(mds_2%p)
        for i in range(3):
            diff_0[i] = 3*r0_limbs[i] + r1_limbs[i] + r2_limbs[i] - q[0]*p_limbs[i] - mds_0_s[i]
            diff_1[i] = r0_limbs[i] - r1_limbs[i] + r2_limbs[i] - q[1]*p_limbs[i] - mds_1_s[i]
            diff_2[i] = r0_limbs[i] + r1_limbs[i] - 2*r2_limbs[i] - q[2]*p_limbs[i] - mds_2_s[i]
        #print('diff_0', diff_0)
        #print('diff_1', diff_1)
        #print('diff_2', diff_2)
        _, carries_0 = reduce_zero_poly(diff_0)
        _, carries_1 = reduce_zero_poly(diff_1)
        _, carries_2 = reduce_zero_poly(diff_2)
        carries_0 = abs_poly(carries_0)
        carries_1 = abs_poly(carries_1)
        carries_2 = abs_poly(carries_2)
        for i in range(2):
            setattr(ids, 'mds_0_c'+str(i), carries_0[i])
            setattr(ids, 'mds_1_c'+str(i), carries_1[i])
            setattr(ids, 'mds_2_c'+str(i), carries_2[i])
        for i in range(3):
            setattr(ids, 'q'+str(i), q[i])
        for i in range(ids.N_LIMBS):
            setattr(ids.mds_mul0, 'd'+str(i), mds_0_s[i])
            setattr(ids.mds_mul1, 'd'+str(i), mds_1_s[i])
            setattr(ids.mds_mul2, 'd'+str(i), mds_2_s[i])
        for i in range(2):
            setattr(ids,'mds_0_flag'+str(i), 1 if diff_0[i] >= 0 else 0)
            setattr(ids,'mds_1_flag'+str(i), 1 if diff_1[i] >= 0 else 0)
            setattr(ids,'mds_2_flag'+str(i), 1 if diff_2[i] >= 0 else 0)
    %}

    assert [range_check_ptr] = 4 - q0;
    assert [range_check_ptr + 1] = 2 - q1;
    assert [range_check_ptr + 2] = 2 - q2;
    assert [range_check_ptr + 3] = BASE_MIN_1 - mds_mul0.d0;
    assert [range_check_ptr + 4] = BASE_MIN_1 - mds_mul0.d1;
    assert [range_check_ptr + 5] = P2 - mds_mul0.d2;
    assert [range_check_ptr + 6] = BASE_MIN_1 - mds_mul1.d0;
    assert [range_check_ptr + 7] = BASE_MIN_1 - mds_mul1.d1;
    assert [range_check_ptr + 8] = P2 - mds_mul1.d2;
    assert [range_check_ptr + 9] = BASE_MIN_1 - mds_mul2.d0;
    assert [range_check_ptr + 10] = BASE_MIN_1 - mds_mul2.d1;
    assert [range_check_ptr + 11] = P2 - mds_mul2.d2;
    assert [range_check_ptr + 12] = mds_0_c0;
    assert [range_check_ptr + 13] = mds_0_c1;
    assert [range_check_ptr + 14] = mds_1_c0;
    assert [range_check_ptr + 15] = mds_1_c1;
    assert [range_check_ptr + 16] = mds_2_c0;
    assert [range_check_ptr + 17] = mds_2_c1;

    tempvar mds_0_d0_diff = 3 * r0.d0 + r1.d0 + r2.d0 - q0 * P0 - mds_mul0.d0;
    tempvar mds_0_d1_diff = 3 * r0.d1 + r1.d1 + r2.d1 - q0 * P1 - mds_mul0.d1;
    tempvar mds_0_d2_diff = 3 * r0.d2 + r1.d2 + r2.d2 - q0 * P2 - mds_mul0.d2;
    tempvar mds_1_d0_diff = r0.d0 - r1.d0 + r2.d0 - q1 * P0 - mds_mul1.d0;
    tempvar mds_1_d1_diff = r0.d1 - r1.d1 + r2.d1 - q1 * P1 - mds_mul1.d1;
    tempvar mds_1_d2_diff = r0.d2 - r1.d2 + r2.d2 - q1 * P2 - mds_mul1.d2;
    tempvar mds_2_d0_diff = r0.d0 + r1.d0 - 2 * r2.d0 - q2 * P0 - mds_mul2.d0;
    tempvar mds_2_d1_diff = r0.d1 + r1.d1 - 2 * r2.d1 - q2 * P1 - mds_mul2.d1;
    tempvar mds_2_d2_diff = r0.d2 + r1.d2 - 2 * r2.d2 - q2 * P2 - mds_mul2.d2;

    local mds_0_carry0;
    local mds_0_carry1;
    local mds_1_carry0;
    local mds_1_carry1;
    local mds_2_carry0;
    local mds_2_carry1;

    if (mds_0_flag0 != 0) {
        assert mds_0_carry0 = mds_0_c0;
        assert mds_0_d0_diff = mds_0_carry0 * BASE;
    } else {
        assert mds_0_carry0 = (-1) * mds_0_c0;
        assert mds_0_d0_diff = mds_0_carry0 * BASE;
    }
    if (mds_0_flag1 != 0) {
        assert mds_0_carry1 = mds_0_c1;
        assert mds_0_d1_diff + mds_0_carry0 = mds_0_carry1 * BASE;
    } else {
        assert mds_0_carry1 = (-1) * mds_0_c1;
        assert mds_0_d1_diff + mds_0_carry0 = mds_0_carry1 * BASE;
    }
    if (mds_1_flag0 != 0) {
        assert mds_1_carry0 = mds_1_c0;
        assert mds_1_d0_diff = mds_1_carry0 * BASE;
    } else {
        assert mds_1_carry0 = (-1) * mds_1_c0;
        assert mds_1_d0_diff = mds_1_carry0 * BASE;
    }
    if (mds_1_flag1 != 0) {
        assert mds_1_carry1 = mds_1_c1;
        assert mds_1_d1_diff + mds_1_carry0 = mds_1_carry1 * BASE;
    } else {
        assert mds_1_carry1 = (-1) * mds_1_c1;
        assert mds_1_d1_diff + mds_1_carry0 = mds_1_carry1 * BASE;
    }
    if (mds_2_flag0 != 0) {
        assert mds_2_carry0 = mds_2_c0;
        assert mds_2_d0_diff = mds_2_carry0 * BASE;
    } else {
        assert mds_2_carry0 = (-1) * mds_2_c0;
        assert mds_2_d0_diff = mds_2_carry0 * BASE;
    }
    if (mds_2_flag1 != 0) {
        assert mds_2_carry1 = mds_2_c1;
        assert mds_2_d1_diff + mds_2_carry0 = mds_2_carry1 * BASE;
    } else {
        assert mds_2_carry1 = (-1) * mds_2_c1;
        assert mds_2_d1_diff + mds_2_carry0 = mds_2_carry1 * BASE;
    }

    assert mds_0_d2_diff + mds_0_carry1 = 0;
    assert mds_1_d2_diff + mds_1_carry1 = 0;
    assert mds_2_d2_diff + mds_2_carry1 = 0;

    local mds_mul_state: PoseidonState = PoseidonState(s0=&mds_mul0, s1=&mds_mul1, s2=&mds_mul2);
    tempvar range_check_ptr = range_check_ptr + 18;
    return hades_round_partial(&mds_mul_state, round_idx + 1, index + 1);
}

func get_round_constants() -> BigInt3* {
    alloc_locals;
    let (data_address) = get_label_location(data);
    let arr = cast(data_address, BigInt3*);

    return arr;

    data:
    dw 43426927226019481180962437;
    dw 58619926353141091854114408;
    dw 1583428800332345853184455;
    dw 69030734728936869831444681;
    dw 18204390437056155601385672;
    dw 235574211483670036117375;
    dw 40786326899472072784380689;
    dw 52808304889084823609953975;
    dw 2058738470411902648515185;
    dw 65886802791647252362228957;
    dw 6622881092115066699939557;
    dw 980436529515328320603319;
    dw 16278821460675413938656935;
    dw 74142984571000265551852114;
    dw 1173957678316290377629037;
    dw 59359409154855899346933526;
    dw 71297048237435627493464885;
    dw 2092383362178213924303028;
    dw 33070617224523297447123420;
    dw 56757940356654840062539136;
    dw 399844474333167152058161;
    dw 6545056963434242400356497;
    dw 19493094308419381610520818;
    dw 3555492448235709889660315;
    dw 23690066780741826543033679;
    dw 36318357311776488015557811;
    dw 1574594104688085889921890;
    dw 31672213139231040875084387;
    dw 40450830180686795729052173;
    dw 892190596608199170548376;
    dw 76619635970410606233286890;
    dw 1441349082682694924823227;
    dw 2209199073069521222054154;
    dw 37262589947027592523284177;
    dw 23904765894760847254877870;
    dw 879301656905941540903501;
    dw 6763868825108495671092656;
    dw 6609668131684966623560699;
    dw 2155775271630672358501417;
    dw 35475889871411848489234458;
    dw 51670237676715955060691419;
    dw 615185720745863898270993;
    dw 49980969336197998961115054;
    dw 55379179435886344513472706;
    dw 3287830725382860173260335;
    dw 29672110914861435684894616;
    dw 18417294261338315820278643;
    dw 941500672134320859424035;
    dw 15481013558156831273946292;
    dw 8315274471391954836187264;
    dw 1587129569908546158113548;
    dw 62450078477711418325276680;
    dw 37393552362426113559047873;
    dw 469302855426161348326790;
    dw 27126515766813962431805508;
    dw 41218343842076947301041124;
    dw 3079199293143351505108816;
    dw 53099764217436972253680468;
    dw 7747063375818223028967737;
    dw 267347388078296247199365;
    dw 24124471475827603674633208;
    dw 74903185017645243559053289;
    dw 681198131246842114373606;
    dw 69051766835478248875946023;
    dw 34556603703692306634305955;
    dw 1795794496641489375176100;
    dw 48402576628264850137827741;
    dw 16310414803984134890998137;
    dw 981670703279179975051925;
    dw 16083187679175695699271453;
    dw 10043353372964562526751600;
    dw 2252522570656945618495000;
    dw 59135072457747483352016735;
    dw 52574669672838781169182432;
    dw 2903648012311488695327691;
    dw 58467625716029403954057894;
    dw 28807127918978612112234455;
    dw 3431044790470201897171340;
    dw 58522193259537504449227146;
    dw 30252360779696044920545592;
    dw 24907158083380381617300;
    dw 69351939665538842494302239;
    dw 12153288780963687313500689;
    dw 630154403643328857999116;
    dw 77352270180228750254294367;
    dw 17382310137074451349552311;
    dw 310624483514428599423616;
    dw 702254355634910427274432;
    dw 14018384818609295878008074;
    dw 1011770973721593462696488;
    dw 62447131593510355363303843;
    dw 71273777384078462599354998;
    dw 2261135821347484477169706;
    dw 30852222459540006946318594;
    dw 41806485210625722830367042;
    dw 528921416794207527052075;
    dw 39077978786774879222249330;
    dw 8685559010461996853899406;
    dw 647828921943865802028774;
    dw 15522673072391766114611954;
    dw 8717609910278001202052719;
    dw 540395012682613067880728;
    dw 57713505965068814699605294;
    dw 74957130177839208860650448;
    dw 709135911810799198920766;
    dw 20710540576944857767092377;
    dw 26351241575460505899776017;
    dw 2471890927170120818097488;
    dw 49815748096607927336216312;
    dw 20038152117374680585946498;
    dw 650438185496791183354065;
    dw 56236596580243102526375987;
    dw 64494300687670355537719806;
    dw 3615221036305986444581992;
    dw 74309730960709136431213528;
    dw 27240671045796719091390334;
    dw 772108755306002791147430;
    dw 17611765077545860152018415;
    dw 13234648704385083367388132;
    dw 2462056269678437902608852;
    dw 71348546877455292801485322;
    dw 1637299559410673169202120;
    dw 440186059369595164120764;
    dw 13585335337439410997904466;
    dw 63835659667981218042989414;
    dw 3185729494269582628218494;
    dw 11085011420946178995143902;
    dw 38716722578148968310798543;
    dw 2108547509946384945964032;
    dw 49020888354653322014996951;
    dw 18325658657822179104624362;
    dw 734281501949933276065728;
    dw 15959899460139269845872412;
    dw 47643275777483079629445651;
    dw 2314653924096449014188394;
    dw 14599053184711686667373280;
    dw 4222691710657837585374522;
    dw 359582212318545454144201;
    dw 3428187037403810016447084;
    dw 56452531206275346176397993;
    dw 1100043706331717268552706;
    dw 14865953587472912262204278;
    dw 51959878880162875206773362;
    dw 359674337526966079824835;
    dw 75987181748446503718788198;
    dw 68694757127837720768741923;
    dw 1226211981984382797165607;
    dw 18306010313373525095480321;
    dw 76748744081744633943494437;
    dw 2124493757733478957124786;
    dw 69974151683846965463311061;
    dw 77002447411748234148041523;
    dw 900872660006913541536782;
    dw 42322077502674562617213260;
    dw 73685477279237896857465123;
    dw 1206363998923480608007647;
    dw 76270997033019693250122229;
    dw 73705049688354787142995668;
    dw 1379668935162139281011722;
    dw 58849991555679421544324034;
    dw 31941535945928714483599883;
    dw 1548931585682060318945536;
    dw 21093653246501000047039168;
    dw 46927209872808901696425937;
    dw 1837363366241855271999092;
    dw 61029529637669283436370722;
    dw 55039372517948328552672446;
    dw 2581455282627863066156310;
    dw 21080582952087246202143600;
    dw 57001696787483821222752645;
    dw 915243112677203319450827;
    dw 25335489146544506253568071;
    dw 73150140946811708533064796;
    dw 1146661848265730245770158;
    dw 19319916820963911989597336;
    dw 10716093331690205093448183;
    dw 2026878825367926459022996;
    dw 15238002398279100857858572;
    dw 54799180609572566772709159;
    dw 728868766226600940745774;
    dw 12639644231107516831183493;
    dw 51712310007239247268937990;
    dw 2806313671494898996652464;
    dw 29281091251811977607220373;
    dw 1191277561267661527124289;
    dw 579138487951266458261353;
    dw 35204033296468979179925369;
    dw 57996893218676289227501500;
    dw 1680908691884809991284439;
    dw 68845732618241567166712396;
    dw 39434335590748924509135596;
    dw 977109757499078754169279;
    dw 23474797695964881721085961;
    dw 7010554528822364388800066;
    dw 3083717985735652314313542;
    dw 19805006184880923898872379;
    dw 35336744497180946113990089;
    dw 1639089807266309346735016;
    dw 69098347982845207681256928;
    dw 51763265721686869973974445;
    dw 565932723988476823664297;
    dw 6838875469851307383596985;
    dw 19183501226640887489303593;
    dw 882653963471726905329639;
    dw 28912418610580181609976811;
    dw 50756268288228132879302775;
    dw 2414003366406332113488186;
    dw 11691108718169039118960535;
    dw 3779153801219080093498988;
    dw 2107022852348108294187904;
    dw 35659453523760535942820092;
    dw 34907457388510304210003179;
    dw 1040419360433693577463800;
    dw 59942592445938051127821517;
    dw 27826994555829489798464862;
    dw 1249901116383061180821068;
    dw 17917550092999197485609386;
    dw 11361675024695413933961080;
    dw 3116351752572985773745912;
    dw 13215969158733470032648448;
    dw 67683971190710730823190570;
    dw 3332423110706516445507650;
    dw 62891524353529935666334766;
    dw 50610555277728490057188958;
    dw 2316297809181877003656221;
    dw 11650733714027633783745410;
    dw 4057458657369677034598313;
    dw 3240502312081374446528987;
    dw 9477640992335692203175000;
    dw 25570820035894890412876646;
    dw 707306233982218815658951;
    dw 59334278313492083212912178;
    dw 39241044486849916717852585;
    dw 2132135969332794601236243;
    dw 63641810455138584857925074;
    dw 29064225848891599496594516;
    dw 1316746406834902042281709;
    dw 74943735965709970801739374;
    dw 8615630375008644503637157;
    dw 947129719156361697591994;
    dw 27950944125925653645580836;
    dw 46106949725829096242248239;
    dw 2839601841505098444828778;
    dw 64822629711559234170823853;
    dw 68874683407995373942045540;
    dw 655479295530279610061468;
    dw 21203590000716333953946948;
    dw 27581188272617393276719798;
    dw 1444938467761122974184817;
    dw 37267753631151487387425045;
    dw 46093695076895555699353565;
    dw 1853502557859005685666425;
    dw 63951893610769605030923180;
    dw 41904499403341226493800267;
    dw 1158616642510616898138717;
    dw 49355536215396683615246292;
    dw 51272653893499887608843807;
    dw 1170950094244225781026264;
    dw 68329208358997335464197998;
    dw 66458483842889521916804956;
    dw 2399099315364143392601282;
    dw 60424466181965471499708332;
    dw 65584519875919984655250409;
    dw 1051856332961270346408993;
    dw 14967835829208858699239012;
    dw 33273887927414581597874009;
    dw 2313503547111990354770309;
    dw 30951730652682948177940128;
    dw 62402719901675894820391128;
    dw 72617151631873293023144;
    dw 37791940997524228714282369;
    dw 53010570636282442975591562;
    dw 2778631315525659372528539;
    dw 44782234147067015124547749;
    dw 54023410605190081847485297;
    dw 2162423601487233358311259;
    dw 20440417108876050826604877;
    dw 46720452094399449305781150;
    dw 2193721368348387015644108;
    dw 52651100087181904340259565;
    dw 50922400984681786350633639;
    dw 534115628651222170323569;
    dw 59782969389955180110381891;
    dw 16888998773076586307652347;
    dw 203704707897558706027607;
    dw 11833709146992240092926191;
    dw 10904751158293564129292525;
    dw 583646951400912835449802;
    dw 27378396103426734938260247;
    dw 40125213820471860188851819;
    dw 2919153762792977429353512;
    dw 23981609855062720770869355;
    dw 46962948484744176282742391;
    dw 2421579303772795440557662;
    dw 43782347635628023407636217;
    dw 51190393178448709371781469;
    dw 488526694232182376303234;
    dw 1467230476997215406284891;
    dw 3596359756571654202750214;
    dw 773146639614853083641589;
    dw 37169702405102867465607038;
    dw 51583792035517791412509638;
    dw 3540016307411595157655177;
    dw 73721734306452208667368295;
    dw 48006706320372327800936067;
    dw 2831662616600394675369414;
    dw 20738690859116315746338878;
    dw 26725562810099446427776590;
    dw 3276424545607777597929407;
    dw 23310072781712178285548047;
    dw 77083186492563186350394778;
    dw 3242200212103444049489281;
    dw 44603265967752377503137279;
    dw 7575796695437366517387631;
    dw 3583850905396612458009191;
    dw 44757385781447357767403002;
    dw 47452008536538520729053331;
    dw 1298016234236624708545289;
    dw 15787847246629125456402618;
    dw 31027676530277528990619358;
    dw 2750370437573912297130597;
    dw 58570172640744740169087137;
    dw 76478540433659808451367834;
    dw 2918442303390149505451544;
    dw 2390754118713563958271413;
    dw 56553433891856804515863526;
    dw 3098858566234021253479408;
    dw 31330001127271505318514713;
    dw 41564282509519490354730385;
    dw 483773288636448961503800;
    dw 32850120585622835014369207;
    dw 46883629193428800607872887;
    dw 2451476453316640986802689;
    dw 34938157504581693586100958;
    dw 17873228110868980922605747;
    dw 3048401567606818684898999;
    dw 47008959193352598874200266;
    dw 4278239679821089909464967;
    dw 2676833190940588491659689;
    dw 22325995190845534069421346;
    dw 60969209695724284011857999;
    dw 1311469763795398365371577;
    dw 6031905596047366632924279;
    dw 47793981156349148875709623;
    dw 605499781583402540070021;
    dw 66938288994155920398717219;
    dw 19111080657524654158213134;
    dw 2531055852268366279471626;
    dw 14619852593319916294178521;
    dw 16215078529624339960916513;
    dw 2326761666457973962013884;
    dw 2954558696602306153944669;
    dw 20541181974476654331481368;
    dw 2746018236161890890480311;
    dw 68695292419446581863627766;
    dw 58545280552966838794666980;
    dw 2380705824152005080048574;
    dw 65491793015924352042572264;
    dw 18496920805649102292528475;
    dw 260329871830155297596682;
    dw 68422086736796121284403176;
    dw 56443648501049882543704972;
    dw 1795607416991188398929049;
    dw 42471944890485445741786845;
    dw 48658968145161143115592921;
    dw 2732064716300823487753784;
    dw 37283302415277845093625827;
    dw 13904592955930155517987998;
    dw 3119535065362475680686434;
    dw 39780349150307571370829916;
    dw 75417509222521052947698623;
    dw 42961291238417050862152;
    dw 71718330690492546049761591;
    dw 72041309525135758136261157;
    dw 1660582427758693251515188;
    dw 10987002486149426425366012;
    dw 29586808489156158602301261;
    dw 216032876479308995226603;
    dw 22986504271472405898512380;
    dw 38384185851794708982806089;
    dw 643928330282532565682406;
    dw 5000635195247213540877739;
    dw 33932441108934895761699905;
    dw 2073428932641365471679943;
    dw 57795943015066908447140127;
    dw 12373835255617510661716632;
    dw 2379485085768202268787294;
    dw 51036659023452627830371819;
    dw 31374121750762076052907939;
    dw 445094598173437092412458;
    dw 9017384767365435301721977;
    dw 48926949160806243798579550;
    dw 2306062733755704361658095;
    dw 51420280541804358634355414;
    dw 38666585563847286880125257;
    dw 2569594802515837714701140;
    dw 65575707154639998347463415;
    dw 17364237213655401645445758;
    dw 641056877218678513116772;
    dw 71698388712893690432813506;
    dw 7126685431870074869104823;
    dw 2543379945575290474436061;
    dw 54226579201976254891847194;
    dw 9335410004890897393292971;
    dw 2428552778378752507869691;
    dw 5519895127835083390891353;
    dw 42972472341607570019759267;
    dw 903842891554495412269157;
    dw 55026141938048287397745245;
    dw 66911890823629177695320571;
    dw 2450145367808176844876945;
    dw 59640802477560021970448801;
    dw 27927840275746297004663963;
    dw 466357247823498241177570;
    dw 44202989030288103647988447;
    dw 50036084226060767210610875;
    dw 608463023350296898173986;
    dw 35186635456224003777367437;
    dw 18568316347057779060171050;
    dw 294369625776366551871583;
    dw 47142741549231390851402861;
    dw 7611429404288443925208631;
    dw 335621756466237987317989;
    dw 25331439942306113379354799;
    dw 28922568783925431330079289;
    dw 3306123624391342852975700;
    dw 27301623956212930526787640;
    dw 40485428184705437170717419;
    dw 1873582622765132339902628;
    dw 30045479013636163723836751;
    dw 51293518878140632928157279;
    dw 1025091816784956879697691;
    dw 22898595442287336724393476;
    dw 56344495574344390830587864;
    dw 3131332465775348588965464;
    dw 32302363213812099454311160;
    dw 6173679121560280343213241;
    dw 739343682334322715635048;
    dw 48055604970159296847460437;
    dw 60330924525864125971730472;
    dw 3124776217858675195714199;
    dw 45471520435947376335898247;
    dw 1668268417587313544825733;
    dw 2179511046865634800634243;
    dw 54824645759707712915820467;
    dw 60340246858531925580839920;
    dw 1063556304799070427447940;
    dw 31715958015473628090226783;
    dw 30834666465462612407720085;
    dw 2002022957184601860609047;
    dw 39327741312847635269935650;
    dw 39080564100914936823051202;
    dw 1034085039808822396509680;
    dw 55061147331736987791056219;
    dw 47269864229787565443407577;
    dw 576910808407835616583541;
    dw 1203443104836848953179895;
    dw 99393512262437629026696;
    dw 584909790241721518125397;
    dw 2194674399521097971551836;
    dw 38481047087461176472697100;
    dw 111478054801344301617186;
    dw 73572187982389259804051670;
    dw 21872446909734557653319411;
    dw 1749951266304143413048820;
    dw 52636543508963321651079261;
    dw 30196273621913235755724209;
    dw 187445314799373392213539;
    dw 44532672569006263610860150;
    dw 57195661608759332217514583;
    dw 3103674663225176497164966;
    dw 19345640053597834689154666;
    dw 8432870535564165775590747;
    dw 1879536096161896267898551;
    dw 63292155602359738483049859;
    dw 2950411344465948177537059;
    dw 3206724694111615589808477;
    dw 27940887216275905708168778;
    dw 36173700084882587716626776;
    dw 3075530913123553666268016;
    dw 53524580929827304124093648;
    dw 40629837835350107885511871;
    dw 1056931411161857565813780;
    dw 63942713608751328564014220;
    dw 57201052734286949414685909;
    dw 2923516764219315813054189;
    dw 24052470481550879326590209;
    dw 4020813517821080261358786;
    dw 3502984628662505169497769;
    dw 8925779889434238344206812;
    dw 2871772569451587707965789;
    dw 1496094480735613173354330;
    dw 36868039121066682875679151;
    dw 27761522480934441451252849;
    dw 681864371222846173124070;
    dw 3890326606400230706959583;
    dw 3104675849411364599190680;
    dw 726925910203146686798971;
    dw 14054332817725525288599605;
    dw 70515775651706934957729940;
    dw 2942586915956914122755009;
    dw 61630991035115878450116294;
    dw 46109050275017885993200756;
    dw 778941507326524195187733;
    dw 47058376182407093936118117;
    dw 57210236873450172598350409;
    dw 3370884445547042053866738;
    dw 7706347405421683782432362;
    dw 64163911298109139591288097;
    dw 2838648205999116618080882;
    dw 55624312808172855730468734;
    dw 61986481824684754913445399;
    dw 96163439253890097481122;
    dw 62079517090952151096453829;
    dw 28397461231334480648743674;
    dw 317433987050512345171886;
    dw 48080563852744674747800720;
    dw 28190784461753638613011083;
    dw 3193301735816837067675501;
    dw 33105837638538667418842119;
    dw 35222259349155636147814414;
    dw 326042153199076305442490;
    dw 45389483322083471211292130;
    dw 21184167454118022797568170;
    dw 68745115631485591896771;
    dw 50680638800950476482661722;
    dw 42775779587415243478434441;
    dw 743712435393446576705146;
    dw 51874375867508855357800827;
    dw 68491451546660257467847978;
    dw 191126247955248719670373;
    dw 20198217529762429883736975;
    dw 68877712515003130470148446;
    dw 2883218249189290511314310;
    dw 10495675942863014103049094;
    dw 53773385814381538474848281;
    dw 3318344698105860685858454;
    dw 16787925370276789839865769;
    dw 29041829916307908479447606;
    dw 2796658022274491653229304;
    dw 69272818707920177133264604;
    dw 53771245416182261377430124;
    dw 277480161654430441441225;
    dw 58915841198706395506343429;
    dw 68615066133349962531126934;
    dw 563267555288317092679934;
    dw 47353779876805299686728966;
    dw 31930982855229225967793537;
    dw 2320226283456881766586400;
    dw 34535116370352602017299877;
    dw 8622734349175937361235347;
    dw 48756192055306650081540;
    dw 62042937076523290115382265;
    dw 67520899738487961583188907;
    dw 1814315793995016640955930;
    dw 44445514687645060677766796;
    dw 37114272340860046051749781;
    dw 1030865539580910954650069;
    dw 8657545362183893537951182;
    dw 2201316992363984106127560;
    dw 496661847315206196632574;
    dw 75607709416803697312562220;
    dw 50389168986846797720843020;
    dw 1788728978055769151392867;
    dw 33625740428771268471263022;
    dw 44530042953907604178404060;
    dw 577472765856240678381061;
    dw 15227243237268391841526782;
    dw 15169435303607246620335354;
    dw 28649486088507599798494;
    dw 16449116433577534563761487;
    dw 22087028121228261694346500;
    dw 2905042269309371295779144;
    dw 27605824330480852800452963;
    dw 16756786699322753036202435;
    dw 937391149498804222505252;
    dw 39014389656581511976669779;
    dw 31277272032306602136121856;
    dw 2974914329749126249405874;
    dw 70560153725820965591485887;
    dw 62818075898585739201886819;
    dw 157672166549160477604788;
    dw 30221538500102844119347;
    dw 60894777720333663777806907;
    dw 859652094566693767904827;
    dw 47655863840822757117796517;
    dw 75193351193753480021822436;
    dw 669972515814894654185444;
    dw 31995002471938594263722219;
    dw 3686519757263553646760766;
    dw 1963366052798317248446486;
    dw 53804004752976727965571773;
    dw 34401938183632415224394009;
    dw 3297068248174393220846454;
    dw 20510523593929077797417581;
    dw 75416680859188879978337311;
    dw 751830395444367076394476;
    dw 13300002420768915937807435;
    dw 28141203286453742646976149;
    dw 3023129622571293923588163;
    dw 59917146536008415178022687;
    dw 50138023705651564794381118;
    dw 3470617163073988016810564;
    dw 32187470221037122039060615;
    dw 2409451849890904006612270;
    dw 601514799914278298047003;
    dw 64006621051908976973605856;
    dw 18538395954191711134723668;
    dw 1554885160238251043015909;
    dw 47316210851860444207320023;
    dw 22877275881927530206377357;
    dw 366005315927549761018531;
    dw 14091804640407068473240452;
    dw 69314044486531119341454205;
    dw 2525076891421561656031420;
    dw 64746685795583632145624277;
    dw 16657510038301925022386184;
    dw 1599352711729026270873398;
    dw 38560691344767840971887349;
    dw 40125619857831766258747789;
    dw 3186784346778246055135031;
    dw 4896733539173034016182137;
    dw 26171518754260748479631603;
    dw 2622380795886063061336882;
    dw 29286223278040873417682725;
    dw 320773684411659908353869;
    dw 357185193342567660168900;
    dw 62774912553510476213684898;
    dw 10718678745065581055230880;
    dw 3354039555226951690908943;
    dw 47104997381722471599897648;
    dw 42290652036681016911465490;
    dw 3316791352862326675997878;
    dw 26207871801351017904598848;
    dw 22768473506997907656918651;
    dw 1897731789090270178366884;
    dw 4861222214800576851496401;
    dw 69157640772903201189299755;
    dw 1504058105679443047617425;
    dw 60839114210795166866876137;
    dw 52306317687009241114271301;
    dw 1234458539001205195620799;
    dw 3918945100413461683352503;
    dw 8527112890534303578701072;
    dw 830166717604171264259921;
    dw 72571900747162853865594979;
    dw 28133406685538532913792974;
    dw 3024854239777484344270019;
    dw 3239606491106029033279740;
    dw 65196729045933428375943248;
    dw 176204566456771854308910;
    dw 41069110323971747442389430;
    dw 6897904067350064013026046;
    dw 600648893601709774353660;
    dw 63286354783241518580400431;
    dw 70829889802413809152033809;
    dw 578710422469750536516223;
    dw 2992700564244786311422778;
    dw 70449904207654240176314922;
    dw 2797646619569677036259848;
    dw 75976705496043236693969593;
    dw 1061055689025741739715107;
    dw 1924934303480620600750368;
    dw 17469935735214299280280667;
    dw 52477837379363288837297190;
    dw 3092912814688863444309367;
    dw 70636854274014908879475621;
    dw 26996188890232470337212991;
    dw 2043462164254748685270381;
    dw 53596929708156026928248249;
    dw 36339101850688294090858145;
    dw 3163976246652972670095415;
    dw 60017762319704879506252403;
    dw 1480986733444295126407195;
    dw 816119914400911713201520;
    dw 75263618041573414330565389;
    dw 2920198519431519148242076;
    dw 2323854293250755129384747;
    dw 14337854682902966724993753;
    dw 37694923209612776465371819;
    dw 3479034001394030869937459;
    dw 53779584193827607911532;
    dw 42006264227124340460067218;
    dw 417331408807854656521760;
    dw 60309005884095426836313555;
    dw 60149913140482384035949071;
    dw 1134384923673892811757816;
    dw 15357482968404530806127027;
    dw 68731864917041727414041164;
    dw 3448854976341675972998255;
    dw 56504723129963139464464722;
    dw 50561398649975302263856228;
    dw 2358810940175300081071792;
    dw 65949696873580488321651519;
    dw 37732935013389427688812757;
    dw 3467891668809638238137984;
    dw 32149958795690243795123783;
    dw 63674195664225849881177288;
    dw 2287632691861632159620738;
    dw 72416721669637676270908709;
    dw 13810162484590047036325136;
    dw 2235185313421199693056830;
    dw 54048716299440647119599414;
    dw 13361145892082605470828278;
    dw 3539560840678150212211089;
    dw 10345058476741625245387197;
    dw 9789717233565451998849149;
    dw 641208711724195642752306;
    dw 36401455273334488915469275;
    dw 25197499145013920190950021;
    dw 890787957084236243039810;
    dw 34703061061574076747369887;
    dw 74351847841006269462224361;
    dw 3383583657572702295328204;
    dw 66610083366215707254138072;
    dw 8177600373600922958507969;
    dw 1140360426085517703509825;
    dw 61093886908631884627596440;
    dw 60742283338954085686212763;
    dw 1824926613449933974292420;
    dw 67628520069885816672685166;
    dw 55894730582146096658971742;
    dw 3459061464883578999802372;
    dw 75818864796729589643799320;
    dw 32173774046374550420676819;
    dw 565894355522546814320836;
    dw 53414161196369998701630569;
    dw 71336337024759391197300167;
    dw 2714120466550933946260412;
    dw 25928806147214339572078321;
    dw 55195358967940594702684146;
    dw 1245260637767545871349674;
    dw 48644863861895957550009111;
    dw 64402343091241669991974944;
    dw 1958139608238489624153031;
    dw 48088549440647480752643570;
    dw 66958036888874847556171653;
    dw 3403907516802765249568141;
    dw 64711574352071550660556784;
    dw 8955319740103794070447704;
    dw 2602219575349375543050562;
    dw 22222498566861427232422272;
    dw 14609804453918430313362200;
    dw 3496212404945585726550665;
    dw 37745062412058545704749413;
    dw 64873216506794942537203596;
    dw 440110050832130483065999;
    dw 34880957933203684544921036;
    dw 37543986976134283702841621;
    dw 3638146111047357287415252;
    dw 62119251342346472376636412;
    dw 15115253636942157902145563;
    dw 2443071355840659396196346;
    dw 60487224243736329649357571;
    dw 25867518503490044150920187;
    dw 3287467028610283381917528;
    dw 2217466428477412272812665;
    dw 76512319999987888083251556;
    dw 2160287939685132584633964;
    dw 9243242146156962155990584;
    dw 32808668691976419641815199;
    dw 2570898464677870408743039;
    dw 76844604033460172115127572;
    dw 33072599405352507894135319;
    dw 3567886666506666196409900;
    dw 55386795752117191078670694;
    dw 14657397656656456101234717;
    dw 866237998835731739355165;
    dw 57566368323661738797097064;
    dw 60226427688175684548550398;
    dw 1636580821113543124559080;
    dw 36713676826465835163488804;
    dw 72353124817564582577288337;
    dw 3435099637897278485377251;
    dw 8746325585032664450480922;
    dw 39893619661994666205366140;
    dw 62480801020381488955680;
    dw 35859674116633070235288453;
    dw 48486286661549797369897125;
    dw 1887177889164327931487585;
    dw 7903026515834511948875032;
    dw 60572785390824077321880847;
    dw 420081990475711816829301;
    dw 55606445525784186660450659;
    dw 59758819552533364237359179;
    dw 1677829351883526771187917;
    dw 76800417256621404543916668;
    dw 76505588147233015298921812;
    dw 24732692089387107647012;
    dw 4469295527260460042602750;
    dw 35851354356356822214458810;
    dw 2675370631446367899327381;
    dw 7087634284673806863611820;
    dw 61230585884407135423452295;
    dw 569810780311184471770896;
    dw 61601915611103075494437945;
    dw 34229779963356213732182500;
    dw 2223165697195379557174044;
    dw 51316034862459796649090674;
    dw 29907028137706077795171438;
    dw 1981204340793840581281601;
    dw 56654705812216581136615791;
    dw 57497923577815634296013047;
    dw 348216521279936205695671;
    dw 57701443505351252669022239;
    dw 2050139030055373420373886;
    dw 327508245415296854029759;
    dw 76142257509014400892148260;
    dw 2070943076180049022932990;
    dw 1498025357168200697977474;
    dw 480991387525158707633551;
    dw 63847728058338334587078605;
    dw 3429619074049887822273986;
    dw 45703989146828137062406066;
    dw 30140372876301389812954849;
    dw 2137414917036922759548418;
    dw 58681190816104169221327979;
    dw 50003204260539216458536577;
    dw 978371468006168016002562;
}
