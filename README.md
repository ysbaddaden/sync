# Sync

Synchronization primitives to build concurrent-safe and parallel-safe data
structures in Crystal, so we can embrace MT with more serenity.

## Status

Experimental: in progress work to flesh out sync primitives that we may want to
have in Crystal's stdlib at some point.

The implementations follow basic and naive algorithms. They're far from being
optimized and efficient.

## Primitives

- `Sync::Safe` to annotate types as (a)sync safe.

- `Sync::Mutex` to protect critical sections using mutual exclusion.
- `Sync::RWLock` to protect critical sections using shared access and mutual
  exclusion.

- `Sync::Exclusive(T)` to protect a value `T` using mutual exclusion.
- `Sync::Shared(T)` to protect a value `T` using a mix of shared access and
  mutual exclusion.
- `Sync::Future(T)` to delegate the computation of a value `T` to another fiber.

### TODO

- [ ] `Sync::Semaphore`
- [ ] `Sync::ConditionVariable`
- [ ] `Sync::Condition(T)`
- [ ] `Sync::Map(K, V)`

## License

Distributed under the Apache-2.0 license. Use at your own risk.
