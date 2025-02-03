module dex_contract::router_v3 {

    use std::signer;
    use std::vector;
    use aptos_std::comparator;
    use aptos_framework::coin;
    use aptos_framework::fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store::ensure_primary_store_exists;
    use dex_contract::pool_v3::LiquidityPoolV3;

    use dex_contract::i32;
    use dex_contract::utils;
    use dex_contract::pool_v3;
    use dex_contract::position_v3;
    use dex_contract::utils::is_sorted;

    const EAMOUNT_A_TOO_LESS: u64 = 200001;
    const EAMOUNT_B_TOO_LESS: u64 = 200002;
    const EAMOUNT_OUT_TOO_LESS: u64 = 200003;
    const EAMOUNT_IN_TOO_MUCH: u64 = 200004;
    const ELIQUIDITY_NOT_IN_CURRENT_REGION: u64 = 200005;
    const EMETADATA_NOT_MATCHED: u64 = 200006;
    const EOUT_TOKEN_NOT_MATCHED: u64 = 200007;
    const EOUT_AMOUNT_TOO_LESS: u64 = 200008;
    const EIN_TOKEN_NOT_MATCHED: u64 = 200009;

    /////////////////////////////////////////////////// PROTOCOL ///////////////////////////////////////////////////////
    public entry fun create_pool(
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        fee_tier: u8,
        tick: u32,
    ) {
        pool_v3::create_pool(token_a, token_b, fee_tier, tick);
    }

    public entry fun create_pool_coin<CoinType>(
        token_b: Object<Metadata>,
        fee_tier: u8,
        tick: u32,
    ) {
        create_pool(coin::paired_metadata<CoinType>().extract(), token_b, fee_tier, tick);
    }

    public entry fun create_pool_both_coins<CoinType1, CoinType2>(
        fee_tier: u8,
        tick: u32,
    ) {
        create_pool(
            coin::paired_metadata<CoinType1>().extract(),
            coin::paired_metadata<CoinType1>().extract(),
            fee_tier,
            tick,
        );
    }

    public entry fun create_liquidity(
        lp: &signer,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        fee_tier: u8,
        tick_lower: u32,
        tick_upper: u32,
        tick_current: u32,
        amount_a_desired: u64,
        amount_b_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
        deadline: u64
    ) {
        if(!pool_v3::liquidity_pool_exists(token_a, token_b, fee_tier)) {
            create_pool(token_a, token_b, fee_tier, tick_current);
        };
        let position_obj =
            pool_v3::open_position(lp, token_a, token_b, fee_tier, tick_lower, tick_upper);
        add_liquidity(
            lp,
            position_obj,
            token_a,
            token_b,
            fee_tier,
            amount_a_desired,
            amount_b_desired,
            amount_a_min,
            amount_b_min,
            deadline
        );
    }

    public entry fun create_liquidity_coin<CoinType>(
        lp: &signer,
        token: Object<Metadata>,
        fee_tier: u8,
        tick_lower: u32,
        tick_upper: u32,
        tick_current: u32,
        amount_a_desired: u64,
        amount_b_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
        deadline: u64
    ) {
        let coin_metadata = coin::paired_metadata<CoinType>().extract();
        if(!pool_v3::liquidity_pool_exists(token, coin_metadata, fee_tier)) {
            create_pool(coin_metadata, token, fee_tier, tick_current);
        };
        let position_obj =
            pool_v3::open_position(lp, coin_metadata, token, fee_tier, tick_lower, tick_upper);
        add_liquidity_coin<CoinType>(
            lp,
            position_obj,
            token,
            fee_tier,
            amount_a_desired,
            amount_b_desired,
            amount_a_min,
            amount_b_min,
            deadline
        );
    }

    public entry fun create_liquidity_both_coins<CoinType1, CoinType2>(
        lp: &signer,
        fee_tier: u8,
        tick_lower: u32,
        tick_upper: u32,
        tick_current: u32,
        amount_a_desired: u64,
        amount_b_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
        deadline: u64
    ) {
        let coin_metadata_1 = coin::paired_metadata<CoinType1>().extract();
        let coin_metadata_2 = coin::paired_metadata<CoinType2>().extract();
        if(!pool_v3::liquidity_pool_exists(coin_metadata_1, coin_metadata_2, fee_tier)) {
            create_pool(coin_metadata_1, coin_metadata_2, fee_tier, tick_current);
        };
        let (amount_a_desired, amount_b_desired, amount_a_min, amount_b_min, coin_1_is_token_a)  =
            if (is_sorted(coin_metadata_1, coin_metadata_2)) {
                (amount_a_desired, amount_b_desired, amount_a_min, amount_b_min, true)
            } else {
                (amount_b_desired, amount_a_desired, amount_b_min, amount_a_min, false)
            };
        let position_obj =
            pool_v3::open_position(lp, coin_metadata_1, coin_metadata_2, fee_tier, tick_lower, tick_upper);
        if (coin_1_is_token_a) {
            add_liquidity_both_coins<CoinType1, CoinType2>(
                lp,
                position_obj,
                fee_tier,
                amount_a_desired,
                amount_b_desired,
                amount_a_min,
                amount_b_min,
                deadline
            );
        } else {
            add_liquidity_both_coins<CoinType2, CoinType1>(
                lp,
                position_obj,
                fee_tier,
                amount_a_desired,
                amount_b_desired,
                amount_a_min,
                amount_b_min,
                deadline
            );
        }
    }

    public entry fun open_position(
        lp: &signer,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        fee_tier: u8,
        tick_lower: u32,
        tick_upper: u32,
        _deadline: u64
    ) {
        pool_v3::open_position(
            lp,
            token_a,
            token_b,
            fee_tier,
            tick_lower,
            tick_upper,
        );
    }

    public entry fun open_position_coin<CoinType>(
        lp: &signer,
        token: Object<Metadata>,
        fee_tier: u8,
        tick_lower: u32,
        tick_upper: u32,
        _deadline: u64
    ) {
        pool_v3::open_position(
            lp,
            coin::paired_metadata<CoinType>().extract(),
            token,
            fee_tier,
            tick_lower,
            tick_upper,
        );

    }

    public entry fun open_position_both_coins<CoinType1, CoinType2>(
        lp: &signer,
        fee_tier: u8,
        tick_lower: u32,
        tick_upper: u32,
        _deadline: u64
    ) {
        pool_v3::open_position(
            lp,
            coin::paired_metadata<CoinType1>().extract(),
            coin::paired_metadata<CoinType2>().extract(),
            fee_tier,
            tick_lower,
            tick_upper,
        );
    }

    public entry fun add_liquidity(
        lp: &signer,
        lp_object: Object<position_v3::Info>,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        fee_tier: u8,
        amount_a_desired: u64,
        amount_b_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
        deadline: u64
    ) {
        if(!utils::is_sorted(token_a, token_b)) {
            return add_liquidity(
                lp, lp_object, token_b, token_a, fee_tier,
                amount_b_desired, amount_a_desired, amount_b_min,
                amount_a_min, deadline
            );
        };
        let (tick_lower, tick_upper) = position_v3::get_tick(lp_object);
        let sqrt_price_lower = tick_math::get_sqrt_price_at_tick(tick_lower);
        let sqrt_price_upper = tick_math::get_sqrt_price_at_tick(tick_upper);
        // let current_tick = pool_v3::current_tick(token_a, token_b, fee_tier);
        let current_price = pool_v3::current_price(token_a, token_b, fee_tier);
        let (liquidity_delta, amount_a, amount_b) = if(current_price <= sqrt_price_lower) {
            let liquidity_delta = swap_math::get_liquidity_from_a(
                sqrt_price_lower,
                sqrt_price_upper,
                amount_a_desired,
                false
            );
            let amount_a = swap_math::get_delta_a(
                current_price,
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            (liquidity_delta, amount_a, 0)
        } else if (current_price < sqrt_price_upper) {
            let liquidity_delta_a = swap_math::get_liquidity_from_a(
                current_price,
                sqrt_price_upper,
                amount_a_desired,
                false
            );
            let liquidity_delta_b = swap_math::get_liquidity_from_b(
                sqrt_price_lower,
                current_price,
                amount_b_desired,
                false
            );
            let liquidity_delta = if(liquidity_delta_a <= liquidity_delta_b) {
                liquidity_delta_a
            } else {
                liquidity_delta_b
            };
            let amount_a = swap_math::get_delta_a(
                current_price,
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            let amount_b = swap_math::get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                current_price,
                liquidity_delta,
                true
            );
            (liquidity_delta, amount_a, amount_b)

        } else {
            let liquidity_delta = swap_math::get_liquidity_from_b(
                sqrt_price_lower,
                sqrt_price_upper,
                amount_b_desired,
                false
            );
            let amount_b = swap_math::get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            (liquidity_delta, 0, amount_b)
        };
        let fa_a = primary_fungible_store::withdraw(lp, token_a, amount_a);
        let fa_b = primary_fungible_store::withdraw(lp, token_b, amount_b);
        let(amount_a_input, amount_b_input, fa_a, fa_b) =
            pool_v3::add_liquidity(lp, lp_object, liquidity_delta, fa_a, fa_b);
        assert!(amount_a_input >= amount_a_min, EAMOUNT_A_TOO_LESS);
        assert!(amount_b_input >= amount_b_min, EAMOUNT_B_TOO_LESS);
        primary_fungible_store::deposit(signer::address_of(lp), fa_a);
        primary_fungible_store::deposit(signer::address_of(lp), fa_b);
    }

    public entry fun add_liquidity_coin<CoinType>(
        lp: &signer,
        lp_object: Object<position_v3::Info>,
        token: Object<Metadata>,
        fee_tier: u8,
        amount_a_desired: u64,
        amount_b_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
        _deadline: u64
    ) {
        // cointype -> amount_a
        // token -> amount_b
        let coin_metadata = coin::paired_metadata<CoinType>().extract();
        let (
            token_a,
            token_b,
            coin_is_token_a,
            amount_a_desired,
            amount_b_desired,
            amount_a_min,
            amount_b_min
        ) = if(utils::is_sorted(coin_metadata, token)) {
            (coin_metadata, token, true, amount_a_desired, amount_b_desired, amount_a_min, amount_b_min)
        } else {
            (token, coin_metadata, false, amount_b_desired, amount_a_desired, amount_b_min, amount_a_min)
        };
        let (tick_lower, tick_upper) = position_v3::get_tick(lp_object);
        let sqrt_price_lower = tick_math::get_sqrt_price_at_tick(tick_lower);
        let sqrt_price_upper = tick_math::get_sqrt_price_at_tick(tick_upper);
        // let current_tick = pool_v3::current_tick(token_a, token_b, fee_tier);
        let current_price = pool_v3::current_price(token_a, token_b, fee_tier);
        let (liquidity_delta, amount_a, amount_b) = if(current_price <= sqrt_price_lower) {
            let liquidity_delta = swap_math::get_liquidity_from_a(
                sqrt_price_lower,
                sqrt_price_upper,
                amount_a_desired,
                false
            );
            let amount_a = swap_math::get_delta_a(
                current_price,
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            (liquidity_delta, amount_a, 0)
        } else if (current_price < sqrt_price_upper) {
            let liquidity_delta_a = swap_math::get_liquidity_from_a(
                current_price,
                sqrt_price_upper,
                amount_a_desired,
                false
            );
            let liquidity_delta_b = swap_math::get_liquidity_from_b(
                sqrt_price_lower,
                current_price,
                amount_b_desired,
                false
            );
            let liquidity_delta = if(liquidity_delta_a <= liquidity_delta_b) {
                liquidity_delta_a
            } else {
                liquidity_delta_b
            };
            let amount_a = swap_math::get_delta_a(
                current_price,
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            let amount_b = swap_math::get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                current_price,
                liquidity_delta,
                true
            );
            (liquidity_delta, amount_a, amount_b)
        } else {
            let liquidity_delta = swap_math::get_liquidity_from_b(
                sqrt_price_lower,
                sqrt_price_upper,
                amount_b_desired,
                false
            );
            let amount_b = swap_math::get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            (liquidity_delta, 0, amount_b)
        };
        let(fa_a, fa_b) = if (coin_is_token_a) {
            let fa_a = coin_wrapper::wrap(coin::withdraw<CoinType>(lp, amount_a));
            let fa_b = primary_fungible_store::withdraw(lp, token_b, amount_b);
            (fa_a, fa_b)
        } else {
            let fa_a = primary_fungible_store::withdraw(lp, token_a, amount_a);
            let fa_b = coin_wrapper::wrap(coin::withdraw<CoinType>(lp, amount_b));
            (fa_a, fa_b)
        };
        let(amount_a_input, amount_b_input, fa_a, fa_b) =
            pool_v3::add_liquidity(lp, lp_object, liquidity_delta, fa_a, fa_b);
        assert!(amount_a_input >= amount_a_min, EAMOUNT_A_TOO_LESS);
        assert!(amount_b_input >= (amount_b_min), EAMOUNT_B_TOO_LESS);
        primary_fungible_store::deposit(signer::address_of(lp), fa_a);
        primary_fungible_store::deposit(signer::address_of(lp), fa_b);
    }

    public entry fun add_liquidity_both_coins<CoinType1, CoinType2>(
        lp: &signer,
        lp_object: Object<position_v3::Info>,
        fee_tier: u8,
        amount_a_desired: u64,
        amount_b_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
        _deadline: u64
    ) {
        let coin_metadata_1 = coin::paired_metadata<CoinType1>().extract();
        let coin_metadata_2 = coin::paired_metadata<CoinType2>().extract();
        let (
            token_a,
            token_b,
            coin_type_1_is_token_a,
            amount_a_desired,
            amount_b_desired,
            amount_a_min,
            amount_b_min
        ) = if(utils::is_sorted(coin_metadata_1, coin_metadata_2)) {
            (coin_metadata_1, coin_metadata_2, true, amount_a_desired, amount_b_desired, amount_a_min, amount_b_min)
        } else {
            (coin_metadata_2, coin_metadata_1, false, amount_b_desired, amount_a_desired, amount_b_min, amount_a_min)
        };
        let (tick_lower, tick_upper) = position_v3::get_tick(lp_object);
        let sqrt_price_lower = tick_math::get_sqrt_price_at_tick(tick_lower);
        let sqrt_price_upper = tick_math::get_sqrt_price_at_tick(tick_upper);
        // let current_tick = pool_v3::current_tick(token_a, token_b, fee_tier);
        let current_price = pool_v3::current_price(token_a, token_b, fee_tier);
        let (liquidity_delta, amount_a, amount_b) = if(current_price <= sqrt_price_lower) {
            let liquidity_delta_ = swap_math::get_liquidity_from_a(
                sqrt_price_lower,
                sqrt_price_upper,
                amount_a_desired,
                true
            );
            let amount_a = swap_math::get_delta_a(
                current_price,
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta_,
                true
            );
            (liquidity_delta_, amount_a, 0)
        } else if (current_price < sqrt_price_upper) {
            let liquidity_delta_a = swap_math::get_liquidity_from_a(
                current_price,
                sqrt_price_upper,
                amount_a_desired,
                true
            );
            let liquidity_delta_b = swap_math::get_liquidity_from_b(
                sqrt_price_lower,
                current_price,
                amount_b_desired,
                true
            );
            let liquidity_delta_ = if(liquidity_delta_a <= liquidity_delta_b) {
                liquidity_delta_a
            } else {
                liquidity_delta_b
            };
            let amount_a_ = swap_math::get_delta_a(
                current_price,
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta_,
                true
            );
            let amount_b_ = swap_math::get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                current_price,
                liquidity_delta_,
                true
            );
            (liquidity_delta_, amount_a_, amount_b_)

        } else {
            let liquidity_delta_ = swap_math::get_liquidity_from_b(
                sqrt_price_lower,
                sqrt_price_upper,
                amount_b_desired,
                true
            );
            let amount_b = swap_math::get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta_,
                true
            );
            (liquidity_delta_, 0, amount_b)
        };
        let(fa_a, fa_b) = if (coin_type_1_is_token_a) {
            let fa_a = coin_wrapper::wrap(coin::withdraw<CoinType1>(lp, amount_a));
            let fa_b = coin_wrapper::wrap(coin::withdraw<CoinType2>(lp, amount_b));
            (fa_a, fa_b)
        } else {
            let fa_a = coin_wrapper::wrap(coin::withdraw<CoinType2>(lp, amount_a));
            let fa_b = coin_wrapper::wrap(coin::withdraw<CoinType1>(lp, amount_b));
            (fa_a, fa_b)
        };
        let(amount_a_input, amount_b_input, fa_a, fa_b) =
            pool_v3::add_liquidity(lp, lp_object, liquidity_delta, fa_a, fa_b);
        assert!(amount_a_input >= amount_a_min, EAMOUNT_A_TOO_LESS);
        assert!(amount_b_input >= amount_b_min, EAMOUNT_B_TOO_LESS);
        primary_fungible_store::deposit(signer::address_of(lp), fa_a);
        primary_fungible_store::deposit(signer::address_of(lp), fa_b);
    }

    public entry fun remove_liquidity(
        lp: &signer,
        lp_object: Object<position_v3::Info>,
        liquidity_delta: u128,
        amount_a_min: u64,
        amount_b_min: u64,
        recipient: address,
        _deadline: u64
    ) {
        let (fa_a_opt, fa_b_opt) =
            pool_v3::remove_liquidity(lp, lp_object, liquidity_delta);
        if (fa_a_opt.is_some()) {
            let fa_a = fa_a_opt.destroy_some();
            assert!(fungible_asset::amount(&fa_a) >= amount_a_min, EAMOUNT_A_TOO_LESS);
            primary_fungible_store::deposit(recipient, fa_a);
        } else {
            fa_a_opt.destroy_none();
            assert!(amount_a_min == 0, EAMOUNT_A_TOO_LESS);
        };
        if (fa_b_opt.is_some()) {
            let fa_b = fa_b_opt.destroy_some();
            assert!(fungible_asset::amount(&fa_b) >= amount_b_min, EAMOUNT_B_TOO_LESS);
            primary_fungible_store::deposit(recipient, fa_b);
        } else {
            fa_b_opt.destroy_none();
            assert!(amount_b_min == 0, EAMOUNT_A_TOO_LESS);
        };
    }

    public entry fun remove_liquidity_coin<CoinType>(
        lp: &signer,
        lp_object: Object<position_v3::Info>,
        liquidity_delta: u128,
        amount_a_min: u64,
        amount_b_min: u64,
        recipient: address,
        deadline: u64
    ) {
        remove_liquidity(lp, lp_object, liquidity_delta, amount_a_min, amount_b_min, recipient, deadline);
    }

    public entry fun remove_liquidity_both_coins<CoinType1, CoinType2>(
        lp: &signer,
        lp_object: Object<position_v3::Info>,
        liquidity_delta: u128,
        amount_a_min: u64,
        amount_b_min: u64,
        recipient: address,
        deadline: u64
    ) {
        remove_liquidity(lp, lp_object, liquidity_delta, amount_a_min, amount_b_min, recipient, deadline);
    }

    public entry fun claim_fees(
        lp: &signer,
        lp_objects: vector<address>,
        to: address
    ) {

        let sender = signer::address_of(lp);
        lp_objects.for_each(
        |addr| {
            assert!(
                object::is_owner(
                    object::address_to_object<position_v3::Info>(addr),
                    sender
                )
            );
            let (fa_a, fa_b) =
                pool_v3::claim_fees(lp, object::address_to_object<position_v3::Info>(addr));
            primary_fungible_store::deposit(
                to,
                fa_a,
            );

            primary_fungible_store::deposit(
                to,
                fa_b,
            );
        });
    }



    /////////////////////////////////////////////////// USERS /////////////////////////////////////////////////////////
    /// Swap an amount of fungible assets for another fungible asset. User can specifies the minimum amount they
    /// expect to receive. If the actual amount received is less than the minimum amount, the transaction will fail.
    public entry fun exact_input_swap_entry(
        user: &signer,
        fee_tier: u8,
        amount_in: u64,
        amount_out_min: u64,
        sqrt_price_limit: u128,
        from_token: Object<Metadata>,
        to_token: Object<Metadata>,
        recipient: address,
        _deadline: u64
    ) {
        let pool = pool_v3::liquidity_pool(from_token, to_token, fee_tier);
        let a2b = utils::is_sorted(from_token, to_token);
        let (_token_a, _token_b) = if (a2b) {
            (from_token, to_token)
        } else {
            (to_token, from_token)
        };
        let store =
            primary_fungible_store::primary_store(signer::address_of(user), from_token);
        let (_amount_in, fa_remain, fa_out) = pool_v3::swap(
            pool,
            a2b,
            true,
            amount_in,
            dispatchable_fungible_asset::withdraw(user, store, amount_in),
            sqrt_price_limit
        );
        let amount_out = fungible_asset::amount(&fa_out);
        assert!(amount_out >= amount_out_min, EAMOUNT_OUT_TOO_LESS);
        primary_fungible_store::deposit(recipient, fa_out);
        primary_fungible_store::deposit(recipient, fa_remain);
    }

    /// Swap an amount of coins for fungible assets. User can specifies the minimum amount they expect to receive.
    public entry fun exact_input_coin_for_asset_entry<FromCoin>(
        user: &signer,
        fee_tier: u8,
        amount_in: u64,
        amount_out_min: u64,
        sqrt_price_limit: u128,
        to_token: Object<Metadata>,
        recipient: address,
        deadline: u64
    ) {
        let fa = coin::coin_to_fungible_asset(
            coin::withdraw<FromCoin>(
                user,(coin::balance<FromCoin>(signer::address_of(user)))
            ));
        primary_fungible_store::deposit(
            signer::address_of(user),
            fa
        );
        exact_input_swap_entry(
            user,
            fee_tier,
            amount_in,
            amount_out_min,
            sqrt_price_limit,
            coin::paired_metadata<FromCoin>().extract(),
            to_token,
            recipient,
            deadline
        );
    }

    /// Swap an amount of fungible assets for coins. User can specifies the minimum amount they expect to receive.
    public entry fun exact_input_asset_for_coin_entry<ToCoin>(
        user: &signer,
        fee_tier: u8,
        amount_in: u64,
        amount_out_min: u64,
        sqrt_price_limit: u128,
        from_token: Object<Metadata>,
        recipient: address,
        deadline: u64
    ) {
        exact_input_swap_entry(
            user,
            fee_tier,
            amount_in,
            amount_out_min,
            sqrt_price_limit,
            from_token,
            coin::paired_metadata<ToCoin>().extract(),
            recipient,
            deadline
        );
    }

    /// Swap an amount of coins for another coin. User can specifies the minimum amount they expect to receive.
    public entry fun exact_input_coin_for_coin_entry<FromCoin, ToCoin>(
        user: &signer,
        fee_tier: u8,
        amount_in: u64,
        amount_out_min: u64,
        sqrt_price_limit: u128,
        recipient: address,
        deadline: u64
    ) {
        let fa = coin::coin_to_fungible_asset(
            coin::withdraw<FromCoin>(
                user,(coin::balance<FromCoin>(signer::address_of(user)))
            ));
        primary_fungible_store::deposit(
            signer::address_of(user),
            fa
        );
        exact_input_swap_entry(
            user,
            fee_tier,
            amount_in,
            amount_out_min,
            sqrt_price_limit,
            coin::paired_metadata<FromCoin>().extract(),
            coin::paired_metadata<ToCoin>().extract(),
            recipient,
            deadline
        );
    }

    public entry fun exact_output_swap_entry(
        user: &signer,
        fee_tier: u8,
        amount_in_max: u64,
        amount_out: u64,
        sqrt_price_limit: u128,
        from_token: Object<Metadata>,
        to_token: Object<Metadata>,
        recipient: address,
        _deadline: u64
    ) {
        let pool = pool_v3::liquidity_pool(from_token, to_token, fee_tier);
        let a2b = utils::is_sorted(from_token, to_token);
        let (_token_a, _token_b) = if (a2b) {
            (from_token, to_token)
        } else {
            (to_token, from_token)
        };
        let store =
            primary_fungible_store::primary_store(signer::address_of(user), from_token);
        let (amount_in, fa_remain, fa_out) = pool_v3::swap(
            pool,
            a2b,
            false,
            amount_out,
            dispatchable_fungible_asset::withdraw(user, store, amount_in_max),
            sqrt_price_limit
        );
        let _amount_out = fungible_asset::amount(&fa_out);
        assert!(amount_in <= amount_in_max, EAMOUNT_IN_TOO_MUCH);
        primary_fungible_store::deposit(recipient, fa_out);
        primary_fungible_store::deposit(recipient, fa_remain);
    }

    /// Swap an amount of coins for fungible assets. User can specifies the minimum amount they expect to receive.
    public entry fun exact_output_coin_for_asset_entry<FromCoin>(
        user: &signer,
        fee_tier: u8,
        amount_in_max: u64,
        amount_out: u64,
        sqrt_price_limit: u128,
        to_token: Object<Metadata>,
        recipient: address,
        deadline: u64
    ) {
        let fa = coin::coin_to_fungible_asset(
            coin::withdraw<FromCoin>(
                user,(coin::balance<FromCoin>(signer::address_of(user)))
            ));
        primary_fungible_store::deposit(
            signer::address_of(user),
            fa
        );
        exact_output_swap_entry(
            user,
            fee_tier,
            amount_in_max,
            amount_out,
            sqrt_price_limit,
            coin::paired_metadata<FromCoin>().extract(),
            to_token,
            recipient,
            deadline
        );
    }

    /// Swap an amount of fungible assets for coins. User can specifies the minimum amount they expect to receive.
    public entry fun exact_output_asset_for_coin_entry<ToCoin>(
        user: &signer,
        fee_tier: u8,
        amount_in_max: u64,
        amount_out: u64,
        sqrt_price_limit: u128,
        from_token: Object<Metadata>,
        recipient: address,
        deadline: u64
    ) {
        exact_output_swap_entry(
            user,
            fee_tier,
            amount_in_max,
            amount_out,
            sqrt_price_limit,
            from_token,
            coin::paired_metadata<ToCoin>().extract(),
            recipient,
            deadline
        );
    }

    /// Swap an amount of coins for another coin. User can specifies the minimum amount they expect to receive.
    public entry fun exact_output_coin_for_coin_entry<FromCoin, ToCoin>(
        user: &signer,
        fee_tier: u8,
        amount_in_max: u64,
        amount_out: u64,
        sqrt_price_limit: u128,
        recipient: address,
        deadline: u64
    ) {
        exact_output_swap_entry(
            user,
            fee_tier,
            amount_in_max,
            amount_out,
            sqrt_price_limit,
            coin::paired_metadata<FromCoin>().extract(),
            coin::paired_metadata<ToCoin>().extract(),
            recipient,
            deadline
        );
    }

    public entry fun swap_batch_coin_entry<T>(
        user: &signer,
        lp_path: vector<address>,
        from_token: Object<Metadata>,
        to_token: Object<Metadata>,
        amount_in: u64,
        amount_out_min: u64,
        recipient: address,
    ) {
        let fa = coin::coin_to_fungible_asset(
            coin::withdraw<T>(user,(coin::balance<T>(signer::address_of(user))))
        );
        primary_fungible_store::deposit(
            signer::address_of(user),
            fa
        );
        swap_batch(
            user,
            lp_path,
            from_token,
            to_token,
            amount_in,
            amount_out_min,
            recipient
        )
    }

    public entry fun swap_batch(
        user: &signer,
        lp_path: vector<address>,
        from_token: Object<Metadata>,
        to_token: Object<Metadata>,
        amount_in: u64,
        amount_out_min: u64,
        recipient: address,
    ) {
        let temp_metadata =  from_token;
        let in = primary_fungible_store::withdraw(user, from_token, amount_in);

        lp_path.for_each(|addr|{
            let pool = object::address_to_object<pool_v3::LiquidityPoolV3>(addr);

            let vec_metadata = pool_v3::supported_inner_assets(pool);

            let ( _in_metadata, out_metadata, a2b ) = {
                let one = *vec_metadata.borrow(0);
                let two = *vec_metadata.borrow(1);

                assert!(
                    comparator::compare(&one, &temp_metadata).is_equal() ||
                    comparator::compare(&two, &temp_metadata).is_equal(),
                    EMETADATA_NOT_MATCHED
                );
                if( comparator::compare(&one, &temp_metadata).is_equal() ){
                    ( one, two, true)
                }else {
                    (two, one, false)
                }
            };

            let sqrt_price_limit = if(a2b) {
                tick_math::min_sqrt_price()
            } else {
                tick_math::max_sqrt_price()
            };
            let (_amount_used, remain_in, out) = pool_v3::swap(
                pool,
                a2b,
                true,
                amount_in,
                in,
                sqrt_price_limit
            );

            primary_fungible_store::deposit(signer::address_of(user), remain_in);

            amount_in = fungible_asset::amount(&out);
            in = out;

            temp_metadata = out_metadata;
        });

        let out = in;

        assert!(comparator::compare(&temp_metadata, &to_token).is_equal(), EOUT_TOKEN_NOT_MATCHED);

        assert!(fungible_asset::amount(&out) >= amount_out_min, EOUT_AMOUNT_TOO_LESS);

        primary_fungible_store::deposit(recipient, out);
    }



    ////////////////////////////////////////////// Incentive operation ////////////////////////////////////////////
    ///
    ///
    public entry fun add_coin_rewarder<CoinType>(
        admin: &signer,
        pool: Object<LiquidityPoolV3>,
        emissions_per_second: u64,
        emissions_per_second_max: u64,
        amount: u64
    ) {
        pool_v3::add_rewarder_coin<CoinType>(
            admin,
            pool,
            emissions_per_second,
            emissions_per_second_max,
            amount
        );

    }

    public entry fun add_rewarder(
        admin: &signer,
        pool: Object<LiquidityPoolV3>,
        reward_fa: Object<Metadata>,
        emissions_per_second: u64,
        emissions_per_second_max: u64,
        amount: u64
    ) {
        pool_v3::add_rewarder(
            admin,
            pool,
            reward_fa,
            emissions_per_second,
            emissions_per_second_max,
            amount
        );
    }

    public entry fun add_coin_incentive<CoinType>(
        admin: &signer,
        pool: Object<LiquidityPoolV3>,
        index: u64,
        amount: u64
    ) {
        pool_v3::add_coin_incentive<CoinType>(
            admin,
            pool,
            index,
            amount
        );
    }


    public entry fun add_incentive(
        admin: &signer,
        pool: Object<LiquidityPoolV3>,
        index: u64,
        reward_fa: Object<Metadata>,
        amount: u64
    ) {
        pool_v3::add_incentive(
            admin,
            pool,
            index,
            reward_fa,
            amount
        );
    }

    public entry fun remove_incentive(
        admin: &signer,
        pool: Object<LiquidityPoolV3>,
        index: u64,
        amount: u64
    ) {
        pool_v3::remove_incentive(
            admin,
            pool,
            index,
            amount
        );
    }

    public entry fun update_emissions_rate(
        admin: &signer,
        pool: Object<LiquidityPoolV3>,
        index: u64,
        emissions_per_second: u64
    ) {
        pool_v3::update_emissions_rate(
            admin,
            pool,
            index,
            emissions_per_second
        );
    }

    public entry fun claim_rewards(
        user: &signer,
        position: Object<position_v3::Info>,
        receiver: address
    ) {
        let rewards_list = pool_v3::claim_rewards(user, position);
        let length = vector::length(&rewards_list);
        while(length != 0) {
            length -= 1;
            let fa = vector::pop_back(&mut rewards_list);
            let store =
                ensure_primary_store_exists(receiver, fungible_asset::metadata_from_asset(&fa));
            dispatchable_fungible_asset::deposit(store, fa);
        };
        rewards_list.destroy_empty();
    }

    // TODO: get_amount_by_liquidity_active
    ///////////////////////////////  view  /////////////////////////////////
    #[view]
    public fun get_amount_by_liquidity(position: Object<position_v3::Info>): (u64, u64) {
        let (token_a, token_b, fee_tier) = position_v3::get_pool_info(position);
        let liquidity = position_v3::get_liquidity(position);
        let (tick_lower, tick_upper) = position_v3::get_tick(position);
        let current_tick_index = pool_v3::current_tick(token_a, token_b, fee_tier);
        let current_sqrt_price = pool_v3::current_price(token_a, token_b, fee_tier);
        let (amount_a, amount_b) = swap_math::get_amount_by_liquidity(
            tick_lower,
            tick_upper,
            current_tick_index,
            current_sqrt_price,
            liquidity,
            false
        );
        (amount_a, amount_b)
    }

    #[view]
    public fun optimal_liquidity_amounts(
        tick_lower_u32: u32,
        tick_upper_u32: u32,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        fee_tier: u8,
        amount_a_desired: u64,
        amount_b_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
    ): (u128, u64, u64) {
        if(!utils::is_sorted(token_a, token_b)) {
            let lower = i32::as_u32(i32::round_to_spacing(
                i32::mul(i32::from_u32(tick_upper_u32), i32::neg_from(1)),
                pool_v3::get_tick_spacing(fee_tier),
                false
            ));
            let upper = i32::as_u32(i32::round_to_spacing(
                i32::mul(i32::from_u32(tick_lower_u32), i32::neg_from(1)),
                pool_v3::get_tick_spacing(fee_tier),
                true
            ));
            return optimal_liquidity_amounts(
                lower, upper, token_b, token_a, fee_tier,
                amount_b_desired, amount_a_desired, amount_b_min, amount_a_min
            );
        };
        let tick_lower = i32::from_u32(tick_lower_u32);
        let tick_upper = i32::from_u32(tick_upper_u32);
        let pool_address = pool_v3::liquidity_pool_address(token_a, token_b, fee_tier);
        let (_tick_current, current_price) = pool_v3::current_tick_and_price(pool_address);
        let sqrt_price_lower = tick_math::get_sqrt_price_at_tick(tick_lower);
        let sqrt_price_upper = tick_math::get_sqrt_price_at_tick(tick_upper);
        let (liquidity_delta, amount_a, amount_b) = if(current_price <= sqrt_price_lower) {
            let liquidity_delta = swap_math::get_liquidity_from_a(
                sqrt_price_lower,
                sqrt_price_upper,
                amount_a_desired,
                false
            );
            let amount_a = swap_math::get_delta_a(
                current_price,
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            (liquidity_delta, amount_a, 0)
        } else if (current_price < sqrt_price_upper) {
            let liquidity_delta_a = swap_math::get_liquidity_from_a(
                current_price,
                sqrt_price_upper,
                amount_a_desired,
                false
            );
            let liquidity_delta_b = swap_math::get_liquidity_from_b(
                current_price,
                sqrt_price_upper,
                amount_b_desired,
                false
            );
            let liquidity_delta = if(liquidity_delta_a <= liquidity_delta_b) {
                liquidity_delta_a
            } else {
                liquidity_delta_b
            };
            let amount_a = swap_math::get_delta_a(
                current_price,
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            let amount_b = swap_math::get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                current_price,
                liquidity_delta,
                true
            );
            (liquidity_delta, amount_a, amount_b)

        } else {
            let liquidity_delta = swap_math::get_liquidity_from_b(
                sqrt_price_lower,
                sqrt_price_upper,
                amount_b_desired,
                false
            );
            let amount_b = swap_math::get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            (liquidity_delta, 0, amount_b)
        };
        (liquidity_delta, amount_a, amount_b)
    }

    #[view]
    public fun optimal_liquidity_amounts_from_a(
        tick_lower_u32: u32,
        tick_upper_u32: u32,
        tick_current_u32: u32,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        fee_tier: u8,
        amount_a_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
    ): (u128, u64) {
        if(!is_sorted(token_a, token_b)) {
            return optimal_liquidity_amounts_from_b(
                i32::as_u32(i32::mul(i32::from_u32(tick_upper_u32), i32::neg_from(1))),
                i32::as_u32(i32::mul(i32::from_u32(tick_lower_u32),i32::neg_from(1))),
                i32::as_u32(i32::mul(i32::from_u32(tick_current_u32), i32::neg_from(1))),
                token_b, token_a, fee_tier,
                amount_a_desired, amount_b_min, amount_a_min
            )
        };
        let tick_lower = i32::from_u32(tick_lower_u32);
        let tick_upper = i32::from_u32(tick_upper_u32);
        let sqrt_price_lower = tick_math::get_sqrt_price_at_tick(tick_lower);
        let sqrt_price_upper = tick_math::get_sqrt_price_at_tick(tick_upper);
        // use pool's sqrt price to calculate optimal amounts, alter using input tick current if pool not exist
        let current_price = if(pool_v3::liquidity_pool_exists(token_a, token_b, fee_tier)) {
            let pool_sqrt_price = pool_v3::current_price(token_a, token_b, fee_tier);
            pool_sqrt_price
        } else {
            tick_math::get_sqrt_price_at_tick(i32::from_u32(tick_current_u32))
        };
        let (liquidity_delta, _amount_a, amount_b) = if(current_price <= sqrt_price_lower) {
            let liquidity_delta = swap_math::get_liquidity_from_a(
                sqrt_price_lower,
                sqrt_price_upper,
                amount_a_desired,
                false
            );
            let amount_a = swap_math::get_delta_a(
                current_price,
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            (liquidity_delta, amount_a, 0)
        } else if (current_price < sqrt_price_upper) {
            let liquidity_delta_a = swap_math::get_liquidity_from_a(
                current_price,
                sqrt_price_upper,
                amount_a_desired,
                false
            );
            let amount_b = swap_math::get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                current_price,
                liquidity_delta_a,
                true
            );
            (liquidity_delta_a, amount_a_desired, amount_b)

        } else {
            abort ELIQUIDITY_NOT_IN_CURRENT_REGION;
            (0, 0, 0)
        };
        (liquidity_delta, amount_b)
    }

    #[view]
    public fun optimal_liquidity_amounts_from_b(
        tick_lower_u32: u32,
        tick_upper_u32: u32,
        tick_current_u32: u32,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        fee_tier: u8,
        amount_b_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
    ): (u128, u64) {
        if(!is_sorted(token_a, token_b)) {
            return optimal_liquidity_amounts_from_a(
                i32::as_u32(i32::mul(i32::from_u32(tick_upper_u32), i32::neg_from(1))),
                i32::as_u32(i32::mul(i32::from_u32(tick_lower_u32),i32::neg_from(1))),
                i32::as_u32(i32::mul(i32::from_u32(tick_current_u32), i32::neg_from(1))), token_b, token_a, fee_tier,
                amount_b_desired, amount_b_min, amount_a_min
            )
        };
        let tick_lower = i32::from_u32(tick_lower_u32);
        let tick_upper = i32::from_u32(tick_upper_u32);
        let sqrt_price_lower = tick_math::get_sqrt_price_at_tick(tick_lower);
        let sqrt_price_upper = tick_math::get_sqrt_price_at_tick(tick_upper);
        // use pool's sqrt price to calculate optimal amounts, alter using input tick current if pool not exist
        let current_price = if(pool_v3::liquidity_pool_exists(token_a, token_b, fee_tier)) {
            let pool_sqrt_price = pool_v3::current_price(token_a, token_b, fee_tier);
            pool_sqrt_price
        } else {
            tick_math::get_sqrt_price_at_tick(i32::from_u32(tick_current_u32))
        };
        let (liquidity_delta, amount_a, _amount_b) = if(current_price <= sqrt_price_lower) {
            abort ELIQUIDITY_NOT_IN_CURRENT_REGION;
            (0, 0, 0)
        } else if (current_price < sqrt_price_upper) {
            let liquidity_delta = swap_math::get_liquidity_from_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                current_price,
                amount_b_desired,
                false
            );
            let amount_a = swap_math::get_delta_a(
                current_price,
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            (liquidity_delta, amount_a, amount_b_desired)

        } else {
            let liquidity_delta = swap_math::get_liquidity_from_b(
                sqrt_price_lower,
                sqrt_price_upper,
                amount_b_desired,
                false
            );
            let amount_b = swap_math::get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower),
                tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity_delta,
                true
            );
            (liquidity_delta, 0, amount_b)
        };
        (liquidity_delta, amount_a)
    }

    #[view]
    public fun get_batch_amount_out(
        lp_path: vector<address>,
        amount_in: u64,
        from_token: Object<Metadata>,
        to_token: Object<Metadata>,
    ): u64 {
        let temp_metadata =  from_token;
        let in = amount_in;
        lp_path.for_each(|addr|{
            let pool = object::address_to_object<pool_v3::LiquidityPoolV3>(addr);
            let vec_metadata = pool_v3::supported_inner_assets(pool);

            let ( _, out_metadata ) = {
                let one = *vec_metadata.borrow(0);
                let two = *vec_metadata.borrow(1);
                assert!(comparator::compare(&one, &temp_metadata).is_equal() ||
                    comparator::compare(&two, &temp_metadata).is_equal(), EMETADATA_NOT_MATCHED
                );

                if( comparator::compare(&one, &temp_metadata).is_equal() ){
                    ( one, two )
                } else {
                    (two, one)
                }
            };

            let (amount_out, _ ) = pool_v3::get_amount_out(pool, temp_metadata, in);

            in = amount_out;

            temp_metadata = out_metadata;
        });
        let out = in;

        assert!(comparator::compare(&temp_metadata, &to_token).is_equal(), EOUT_TOKEN_NOT_MATCHED);
        out
    }

    #[view]
    public fun get_batch_amount_in(
        lp_path: vector<address>,
        amount_out: u64,
        from_token: Object<Metadata>,
        to_token: Object<Metadata>
    ): u64 {
        let temp_metadata =  to_token;
        let out = amount_out;
        lp_path.for_each_reverse(|addr|{
            let pool = object::address_to_object<pool_v3::LiquidityPoolV3>(addr);
            let vec_metadata = pool_v3::supported_inner_assets(pool);

            let ( _, in_metadata ) = {
                let one = *vec_metadata.borrow(0);
                let two = *vec_metadata.borrow(1);
                assert!(comparator::compare(&one, &temp_metadata).is_equal() ||
                    comparator::compare(&two, &temp_metadata).is_equal(), EMETADATA_NOT_MATCHED
                );

                if( comparator::compare(&one, &temp_metadata).is_equal() ){
                    ( one, two )
                } else {
                    (two, one)
                }

            };

            let (amount_in, fee) = pool_v3::get_amount_in(pool, temp_metadata, out);

            out = amount_in + fee;

            temp_metadata = in_metadata;
        });
        let in = out;

        assert!(comparator::compare(&temp_metadata, &from_token).is_equal(), EIN_TOKEN_NOT_MATCHED);
        in
    }
}
