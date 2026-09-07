import SingleThreadCore
import Testing

/// One-shot MainActor rendezvous: `wait()` suspends, `resume()` releases.
/// Both sides run on the MainActor, so the FIFO executor ordering makes each
/// test's park/release sequence deterministic.
@MainActor
private final class AsyncGate {
    // MARK: Internal

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    // MARK: Private

    private var continuation: CheckedContinuation<Void, Never>?
}

@MainActor
@Suite(.serialized)
struct StaleReminderRecheckerTests {
    // MARK: - start()

    @Test
    func startFiresImmediateReloadWhenReminderShowing() async {
        let sleepGate = AsyncGate()
        let firstReload = AsyncGate()
        var reloadCount = 0
        let rechecker = StaleReminderRechecker(
            isShowingReminder: { true },
            reload: {
                reloadCount += 1
                if reloadCount == 1 {
                    firstReload.resume()
                }
            },
            // Gated sleep: the first tick's drain runs while the loop is parked,
            // so the assertion below observes exactly one reload. The loop stays
            // parked until `stop()`; releasing the gate afterwards lets a
            // cancelled loop exit without firing a second tick.
            sleep: { _ in await sleepGate.wait() })
        rechecker.start()
        await firstReload.wait()
        #expect(reloadCount == 1)
        rechecker.stop()
        sleepGate.resume()
    }

    @Test
    func pollTickRefiresReloadWhenSleepResolves() async {
        let sleepGate = AsyncGate()
        let firstReload = AsyncGate()
        let secondReload = AsyncGate()
        var reloadCount = 0
        let rechecker = StaleReminderRechecker(
            isShowingReminder: { true },
            reload: {
                reloadCount += 1
                if reloadCount == 1 {
                    firstReload.resume()
                }
                if reloadCount == 2 {
                    secondReload.resume()
                }
            },
            sleep: { _ in await sleepGate.wait() })
        rechecker.start()
        await firstReload.wait() // first tick reload done; loop parked on sleep
        sleepGate.resume() // first poll sleep resolves → second tick
        await secondReload.wait()
        #expect(reloadCount == 2)
        rechecker.stop()
        sleepGate.resume() // release the newly-parked loop post-stop
    }

    // MARK: - Gate

    @Test
    func startIdlesWhileNothingShowing() async {
        let sleepGate = AsyncGate()
        var reloadCount = 0
        let rechecker = StaleReminderRechecker(
            isShowingReminder: { false },
            reload: { reloadCount += 1 },
            sleep: { _ in await sleepGate.wait() })
        rechecker.start()
        await Task.yield() // let the loop run one gate-blocked tick and park
        #expect(reloadCount == 0)
        rechecker.stop()
        sleepGate.resume()
    }

    // MARK: - stop()

    @Test
    func stopIsIdempotentAndCancelsLoop() async {
        let sleepGate = AsyncGate()
        let firstReload = AsyncGate()
        var reloadCount = 0
        let rechecker = StaleReminderRechecker(
            isShowingReminder: { true },
            reload: {
                reloadCount += 1
                if reloadCount == 1 {
                    firstReload.resume()
                }
            },
            sleep: { _ in await sleepGate.wait() })
        rechecker.start()
        await firstReload.wait()
        rechecker.stop()
        rechecker.stop() // second stop is a no-op — must not crash
        sleepGate.resume() // release the parked loop; cancellation suppresses any tick
        await Task.yield()
        #expect(reloadCount == 1)
    }

    @Test
    func stopBeforePendingSleepResolvesCancelsWithoutSecondReload() async {
        let sleepGate = AsyncGate()
        let firstReload = AsyncGate()
        var reloadCount = 0
        let rechecker = StaleReminderRechecker(
            isShowingReminder: { true },
            reload: {
                reloadCount += 1
                if reloadCount == 1 {
                    firstReload.resume()
                }
            },
            sleep: { _ in await sleepGate.wait() })
        rechecker.start()
        await firstReload.wait() // count == 1; loop parked on the unresolved sleep
        rechecker.stop()
        #expect(reloadCount == 1)
        // Cleanup after the assertion: waking a cancelled loop fires no tick.
        sleepGate.resume()
        await Task.yield()
        #expect(reloadCount == 1)
    }

    // MARK: - Coalescing across change ticks

    @Test
    func overlappingChangeTicksCoalesceToSingleTrailingReload() async {
        let fake = FakeChangeSource()
        let sleepGate = AsyncGate()
        let reloadStarted = AsyncGate() // first reload has entered its body
        let releaseReload = AsyncGate() // un-parks the first reload
        let trailingReloadDone = AsyncGate()
        var reloadCount = 0
        let rechecker = StaleReminderRechecker(
            isShowingReminder: { true },
            reload: {
                reloadCount += 1
                if reloadCount == 1 {
                    reloadStarted.resume()
                    await releaseReload.wait() // hold the first reload in flight
                }
                if reloadCount == 2 {
                    trailingReloadDone.resume()
                }
            },
            sleep: { _ in await sleepGate.wait() },
            changeSource: fake)
        rechecker.start()
        await reloadStarted.wait() // reload #1 is now in flight
        fake.fire() // change tick while in flight → reloadPending
        fake.fire() // second overlapping change tick collapses into the same flag
        releaseReload.resume() // reload #1 returns; drain runs the trailing reload
        await trailingReloadDone.wait()
        #expect(reloadCount == 2) // exactly one trailing reload, not three
        rechecker.stop()
        sleepGate.resume() // release the parked loop post-stop
        await Task.yield()
        #expect(reloadCount == 2) // the change handler is unregistered — no third reload
    }
}

/// Records the registered change handler so tests can inject change ticks
/// independently of NotificationCenter.
@MainActor
private final class FakeChangeSource: EventStoreChangedObserving {
    var handler: (@MainActor () -> Void)?

    func onChange(_ handler: @escaping @MainActor () -> Void) -> (() -> Void) {
        self.handler = handler
        return {}
    }

    func fire() {
        handler?()
    }
}
