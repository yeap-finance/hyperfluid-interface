module dex_contract::tick_bitmap {

    use aptos_std::table::{Table};

    use dex_contract::i32::{I32};

    // u32 as tick, higher 24 bits represents words, lower 8 bits represents tick bit position
    // tick need to be
    struct BitMap has store {
        map: Table<I32, u256>
    }

    const U256_MAX: u256 = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    const ETICK_NOT_SUIT_SPACING: u64 = 600001;
    const EMOD_ERROR: u64 = 600002;

}
