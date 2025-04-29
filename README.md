# Sync

Synchronization primitives to build concurrent-safe and parallel-safe data
structures in Crystal, to embrace MT more serenely.

## Status

Experimental: in progress work to flesh out sync primitives that we may want to
have in Crystal's stdlib at some point.

The implementations follow basic and naive algorithms. They're far from being
optimized and efficient.

## Primitives

- `Sync::Safe` (annotation) to mark types as (a)sync safe
- `Sync::Mutex` to protect critical sections using mutual exclusion
- `Sync::RWLock` to protect critical sections using shared access and mutual
  exclusion
- `Sync::Exclusive(T)` to protect a value `T` using mutual exclusion
- `Sync::Shared(T)` to protect a value `T` using a mix of shared access and
  mutual exclusion

### TODO

- `Sync::ConditionVariable`
- `Sync::Future(T)`
- `Sync::Once`

## License

Distributed under the Apache-2.0 license. Use at your own risk.
