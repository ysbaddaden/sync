# Sync

Synchronization primitives to build concurrent-safe and parallel-safe data
structures in Crystal, to embrace MT more serenely.

## Status

Experimental: in progress work to flesh out sync primitives that we may want to
have in Crystal's stdlib at some point.

## Primitives

- `Sync::Safe` (annotation) to mark types as (a)sync safe
- `Sync::Mutex` to protect critical sections using mutual exclusion
- `Sync::RWLock` to protect critical sections using shared access & mutual exclusion
- `Sync::Exclusive(T)` to protect a value `T` using mutual exclusion

### TODO

- `Sync::ConditionVariable`
- `Sync::Shared(T)`
- `Sync::Future(T)`
- `Sync::Once`

## License

Distributed under the Apache-2.0 license. Use at your own risk.
