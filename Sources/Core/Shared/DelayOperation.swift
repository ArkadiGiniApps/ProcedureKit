//
//  DelayOperation.swift
//  Operations
//
//  Created by Daniel Thorpe on 18/07/2015.
//  Copyright © 2015 Daniel Thorpe. All rights reserved.
//

import Foundation

/**
`DelayOperation` is an operation which waits until a given future
date, or a time interval. If the interval is negative, or the date
is in the past, the operation finishes.

Note that this operation efficiently uses `dispatch_after` so it 
does not block the thread on which it is called.

Make an operation dependent on a `DelayOperation` in order to 
make it execute after a timeout, or in a repeated fashion with a
time-out.
*/
public class DelayOperation: Operation {

    internal enum Delay: CustomStringConvertible {
        case Interval(NSTimeInterval)
        case Date(NSDate)

        var interval: NSTimeInterval {
            switch self {
            case .Interval(let _interval): return _interval
            case .Date(let date): return date.timeIntervalSinceNow
            }
        }

        var description: String {
            switch self {
            case .Interval(let _interval):
                return "for \(_interval) seconds"
            case .Date(let date):
                return "until \(NSDateFormatter().stringFromDate(date))"
            }
        }
    }

    private let delay: Delay

    internal init(delay: Delay) {
        self.delay = delay
        super.init()
        name = "Delay \(delay)"
    }

    /**
    Initialize the `DelayOperation` with a time interval.
    
    - parameter interval: a `NSTimeInterval`.
    */
    public convenience init(interval: NSTimeInterval) {
        self.init(delay: .Interval(interval))
    }

    /**
    Initialize the `DelayOperation` with a date.

    - parameter interval: a `NSDate`.
    */
    public convenience init(date: NSDate) {
        self.init(delay: .Date(date))
    }

    /**
    Executes the operation by using dispatch_after to finish the
    operation in the future, but only if the time interval is 
    greater than zero.
    */
    public override func execute() {

        switch delay.interval {

        case (let interval) where interval > 0.0:
            let after = dispatch_time(DISPATCH_TIME_NOW, Int64(interval * Double(NSEC_PER_SEC)))
            dispatch_after(after, Queue.Main.queue) {
                if !self.cancelled {
                    self.finish()
                }
            }
        default:
            finish()
        }
    }


}

