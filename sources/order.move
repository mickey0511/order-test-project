module food_delivery::order {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::vec_map::{Self, VecMap};

    // Order status enum
    const PLACED: u8 = 0;
    const ASSIGNED: u8 = 1;
    const DELIVERED: u8 = 2;
    const CANCELLED_BY_USER: u8 = 3;
    const CANCELLED_BY_RESTAURANT: u8 = 4;

    // Error codes
    const E_INVALID_STATUS: u64 = 0;
    const E_UNAUTHORIZED: u64 = 1;

    // Order struct
    struct Order has key, store {
        id: UID,
        order_id: u64,
        user_address: address,
        status: u8,
        timestamp: u64,
    }

    // State transition history
    struct OrderHistory has key, store {
        id: UID,
        order_id: u64,
        transitions: VecMap<u64, Transition>,
    }

    // Transition struct for history
    struct Transition has store, copy, drop {
        status: u8,
        timestamp: u64,
    }

    // Event emitted on state transition
    struct OrderEvent has copy, drop {
        order_id: u64,
        user_address: address,
        status: u8,
        timestamp: u64,
        tx_digest: vector<u8>,
    }

    // Reputation tracker (Bonus)
    struct Reputation has key, store {
        id: UID,
        user_address: address,
        delivered_count: u64,
        cancelled_count: u64,
    }

    // Initialize reputation for a user
    public entry fun init_reputation(user: address, ctx: &mut TxContext) {
        let reputation = Reputation {
            id: object::new(ctx),
            user_address: user,
            delivered_count: 0,
            cancelled_count: 0,
        };
        transfer::share_object(reputation);
    }

    // Create a new order
    public entry fun create_order(order_id: u64, user: address, clock: &Clock, ctx: &mut TxContext) {
        let order = Order {
            id: object::new(ctx),
            order_id,
            user_address: user,
            status: PLACED,
            timestamp: clock::timestamp_ms(clock),
        };
        let history = OrderHistory {
            id: object::new(ctx),
            order_id,
            transitions: vec_map::empty(),
        };
        vec_map::insert(&mut history.transitions, 0, Transition {
            status: PLACED,
            timestamp: clock::timestamp_ms(clock),
        });
        event::emit(OrderEvent {
            order_id,
            user_address: user,
            status: PLACED,
            timestamp: clock::timestamp_ms(clock),
            tx_digest: tx_context::digest(ctx),
        });
        transfer::share_object(order);
        transfer::share_object(history);
    }

    // Update order status with validation
    public entry fun update_status(
        order: &mut Order,
        history: &mut OrderHistory,
        reputation: &mut Reputation,
        new_status: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(order.order_id == history.order_id, E_INVALID_STATUS);
        assert!(order.user_address == tx_context::sender(ctx) || new_status == CANCELLED_BY_RESTAURANT, E_UNAUTHORIZED);
        assert!(is_valid_transition(order.status, new_status), E_INVALID_STATUS);

        order.status = new_status;
        order.timestamp = clock::timestamp_ms(clock);

        let transition_count = vec_map::size(&history.transitions);
        vec_map::insert(&mut history.transitions, transition_count, Transition {
            status: new_status,
            timestamp: clock::timestamp_ms(clock),
        });

        // Update reputation
        if (new_status == DELIVERED) {
            reputation.delivered_count = reputation.delivered_count + 1;
        } else if (new_status == CANCELLED_BY_USER || new_status == CANCELLED_BY_RESTAURANT) {
            reputation.cancelled_count = reputation.cancelled_count + 1;
        };

        event::emit(OrderEvent {
            order_id: order.order_id,
            user_address: order.user_address,
            status: new_status,
            timestamp: clock::timestamp_ms(clock),
            tx_digest: tx_context::digest(ctx),
        });
    }

    // Validate state transitions
    fun is_valid_transition(current_status: u8, new_status: u8): bool {
        if (current_status == PLACED) {
            return new_status == ASSIGNED || new_status == CANCELLED_BY_USER || new_status == CANCELLED_BY_RESTAURANT
        };
        if (current_status == ASSIGNED) {
            return new_status == DELIVERED || new_status == CANCELLED_BY_USER
        };
        false
    }

    // Getters for frontend
    public fun get_order_status(order: &Order): u8 {
        order.status
    }

    public fun get_order_timestamp(order: &Order): u64 {
        order.timestamp
    }

    public fun get_reputation_counts(reputation: &Reputation): (u64, u64) {
        (reputation.delivered_count, reputation.cancelled_count)
    }
}