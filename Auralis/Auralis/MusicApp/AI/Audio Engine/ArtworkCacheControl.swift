import Foundation
import UIKit

final class ArtworkCacheControl {
    final class ProviderMetrics {
        private let q = DispatchQueue(label: "NowPlayingService.ArtworkProviderMetrics", qos: .utility)
        private var le256: Int = 0
        private var le512: Int = 0
        private var gt512: Int = 0
        func record(requestedMaxDimension: CGFloat) {
            q.async { [requestedMaxDimension] in
                if requestedMaxDimension <= 256 { self.le256 += 1 }
                else if requestedMaxDimension <= 512 { self.le512 += 1 }
                else { self.gt512 += 1 }
            }
        }
        func snapshot() -> (le256: Int, le512: Int, gt512: Int) {
            return q.sync { (le256, le512, gt512) }
        }
        func reset() {
            q.async { self.le256 = 0; self.le512 = 0; self.gt512 = 0 }
        }
    }
    private let lock = NSLock()
    private var _purge = false
    private var _dropMaster = false
    private var _buckets: [Int: UIImage]? = nil
    private var _master: UIImage? = nil
    private var _placeholder: UIImage? = nil
    let metrics = ProviderMetrics()

    var purge: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _purge }
        set { lock.lock(); _purge = newValue; lock.unlock() }
    }
    var dropMaster: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _dropMaster }
        set { lock.lock(); _dropMaster = newValue; lock.unlock() }
    }
    var buckets: [Int: UIImage]? {
        get { lock.lock(); defer { lock.unlock() }; return _buckets }
        set { lock.lock(); _buckets = newValue; lock.unlock() }
    }
    var master: UIImage? {
        get { lock.lock(); defer { lock.unlock() }; return _master }
        set { lock.lock(); _master = newValue; lock.unlock() }
    }
    var placeholder: UIImage? {
        get { lock.lock(); defer { lock.unlock() }; return _placeholder }
        set { lock.lock(); _placeholder = newValue; lock.unlock() }
    }

    func imageFor(requested: CGSize, boundsSize: CGSize) -> UIImage? {
        lock.lock()
        let purge = _purge
        let dropMaster = _dropMaster
        let master = _master
        let placeholder = _placeholder
        let buckets = _buckets
        lock.unlock()

        if purge {
            if dropMaster { return placeholder ?? master }
            return master
        }
        if requested.equalTo(boundsSize) { return master }
        let maxDim = max(requested.width, requested.height)
        let bias: CGFloat = NowPlayingService.bucketBias
        let thresholds = NowPlayingService.bucketThresholds
        let b: Int
        if maxDim <= CGFloat(thresholds[0]) * bias { b = thresholds[0] }
        else if maxDim <= CGFloat(thresholds[1]) * bias { b = thresholds[1] }
        else { b = thresholds[2] }
        if let img = buckets?[b] { return img }
        return master
    }
}
