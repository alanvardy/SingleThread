import EventKit
import SingleThreadCore
import Testing

/// One-shot MainActor rendezvous: `wait()` suspends, `resume()` releases.
/// Both sides run on the MainActor, so the FIFO executor ordering makes each
/// test's park/release sequence deterministic.
/// `resume()` before a `wait()` is buffered (marked `fired`), so a synchronously
/// delivered signal is not lost — `NotificationCenter` delivers to a `.main`
/// queue observer inline on macOS when posted from the main thread.
@MainActor
private final class AsyncGate {
    // MARK: Internal

    func wait() async {
        if fired {
            return
        }
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        guard let continuation else {
            fired = true
            return
        }
        continuation.resume()
        self.continuation = nil
    }

    // MARK: Private

    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false
}

@MainActor
struct EventStoreChangedObserverTests {
    @Test
    func onChangeFiresWhenEventStoreChangedPosted() async {
        let fired = AsyncGate()
        // Use a fresh center, not `.default`: the app-hosted test bundle runs the
        // real app, whose `EKEventStore` posts ambient `.EKEventStoreChanged` on
        // the default center, which would make this non-deterministic. The
        // injected-center seam is also the production wiring.
        let center = NotificationCenter()
        let observer = EventStoreChangedObserver(center: center)
        var count = 0
        let unregister = observer.onChange {
            count += 1
            fired.resume()
        }
        center.post(name: .EKEventStoreChanged, object: nil)
        await fired.wait()
        #expect(count == 1)
        unregister()
    }

    @Test
    func unregisterRemovesObserver() async {
        // Fresh center for the same hermeticity reason as the test above.
        let center = NotificationCenter()
        let observer = EventStoreChangedObserver(center: center)
        var count = 0
        let unregister = observer.onChange { count += 1 }
        unregister()
        center.post(name: .EKEventStoreChanged, object: nil)
        await Task.yield() // allow the .main queue block a chance to run
        #expect(count == 0)
    }
}
