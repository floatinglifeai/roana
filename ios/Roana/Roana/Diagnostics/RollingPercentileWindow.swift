// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

struct RollingPercentileWindow {
    private let capacity: Int
    private var values: [Double] = []

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    mutating func append(_ value: Double) {
        guard value.isFinite else {
            return
        }

        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    func percentile(_ percentile: Double) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        let clamped = min(max(percentile, 0), 1)
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * clamped).rounded())
        return sorted[index]
    }
}
