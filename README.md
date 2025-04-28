# Sync

Synchronization primitives to build concurrent-safe and parallel-safe data
structures in Crystal, to embrace MT more serenely.

## Status

Experimental: in progress work to flesh out sync primitives that we may want to
have in Crystal's stdlib at some point.

## Primitives

- `Sync::Safe` (annotation): mark your types as (a)sync safe.

### TODO

- `Sync::Mutex`
- `Sync::RWLock`
- `Sync::ConditionVariable`
- `Sync::Exclusive(T)`
- `Sync::Shared(T)`
- `Sync::Future(T)`
- `Sync::Once`

## License

Distributed under the Apache-2.0 license. Use at your own risk.
