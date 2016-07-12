//
//  GCDKitTests.swift
//  GCDKitTests
//
//  Copyright © 2014 John Rommel Estropia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import XCTest

@testable
import GCDKit

class GCDKitTests: XCTestCase {
    
    func testGCDBlocks() {
        
        var finishedTasks = 0
        let expectation1 = self.expectation(withDescription: "dispatch block 1")
        let expectation2 = self.expectation(withDescription: "dispatch block 2")
        let expectation3 = self.expectation(withDescription: "dispatch block 3")
        GCDBlock.async(.background) {

            XCTAssertTrue(finishedTasks == 0)
            XCTAssertFalse(Thread.isMainThread())
            XCTAssertTrue(GCDQueue.background.isCurrentExecutionContext())
            expectation1.fulfill()

            finishedTasks += 1
            }
            .notify(.default) {

                XCTAssertTrue(finishedTasks == 1)
                XCTAssertFalse(Thread.isMainThread())
                XCTAssertTrue(GCDQueue.default.isCurrentExecutionContext())
                expectation2.fulfill()

                finishedTasks += 1
            }.notify(.main) {

                XCTAssertTrue(finishedTasks == 2)
                XCTAssertTrue(Thread.isMainThread())
                XCTAssertTrue(GCDQueue.main.isCurrentExecutionContext())
                expectation3.fulfill()
        }

        self.waitForExpectations(withTimeout: 60, handler: nil)
    }

    func testGCDQueue() {

        let mainQueue = GCDQueue.main
        XCTAssertNotNil(mainQueue.dispatchQueue());
        XCTAssertTrue(mainQueue.dispatchQueue().isEqual(DispatchQueue.main))

        let allQueues: [GCDQueue] = [.main, .userInteractive, .userInitiated, .default, .utility, .background, .createSerial("serial"), .createConcurrent("serial")]
        var allQueuesExpectations = [XCTestExpectation]()
        for queue in allQueues {

            if queue != .main {

                queue.sync {

                    XCTAssertTrue(queue.isCurrentExecutionContext())
                    for otherQueue in allQueues {

                        if queue != otherQueue {

                            XCTAssertFalse(otherQueue.isCurrentExecutionContext())
                        }
                    }
                }
            }

            let dispatchExpectation = self.expectation(withDescription: "main queue block")
            allQueuesExpectations.append(dispatchExpectation)

            queue.async {

                XCTAssertTrue(queue.isCurrentExecutionContext())
                for otherQueue in allQueues {

                    if queue != otherQueue {

                        XCTAssertFalse(otherQueue.isCurrentExecutionContext())
                    }
                }
                dispatchExpectation.fulfill()
                }.notify(.main, closure: { () -> Void in

                })
        }

        let dispatchExpectation = self.expectation(withDescription: "main queue block")
        GCDQueue.background.async {

            XCTAssertFalse(Thread.isMainThread())
            dispatchExpectation.fulfill()
        }

        self.waitForExpectations(withTimeout: 60, handler: nil)
    }

    func testGCDGroup() {

        let group = GCDGroup()
        XCTAssertNotNil(group.dispatchGroup());

        let expectation1 = self.expectation(withDescription: "dispatch group block 1")
        let expectation2 = self.expectation(withDescription: "dispatch group block 2")
        group.async(.main) {

            XCTAssertTrue(Thread.isMainThread())
            expectation1.fulfill()
            }
            .async(.default) {

                XCTAssertFalse(Thread.isMainThread())
                expectation2.fulfill()
        }

        let expectation3 = self.expectation(withDescription: "dispatch group block 3")
        group.enter()
        GCDQueue.utility.after(3.0) {

            XCTAssertFalse(Thread.isMainThread())
            expectation3.fulfill()
            group.leave()
        }

        let expectation4 = self.expectation(withDescription: "dispatch group block 4")
        group.enter()
        GCDQueue.default.async {

            XCTAssertFalse(Thread.isMainThread())
            expectation4.fulfill()
            group.leave()
        }

        let expectation5 = self.expectation(withDescription: "dispatch group block 5")
        group.notify(.default) {

            XCTAssertFalse(Thread.isMainThread())
            expectation5.fulfill()
        }
        
        let expectation6 = self.expectation(withDescription: "dispatch group block 6")
        let expectation7 = self.expectation(withDescription: "dispatch group block 7")
        var onceToken = group.enterOnce()
        GCDQueue.createConcurrent("concurrent").apply(2 as UInt) { (iteration) -> Void in
            
            if group.leaveOnce(&onceToken) {
                
                expectation6.fulfill()
            }
            else {
                
                expectation7.fulfill()
            }
        }

        self.waitForExpectations(withTimeout: 60, handler: nil)
    }

    func testGCDSemaphore() {

        let numberOfTasks: UInt = 10
        let semaphore = GCDSemaphore(numberOfTasks)
        XCTAssertNotNil(semaphore.dispatchSemaphore());

        var expectations = [XCTestExpectation]();
        for i in 0 ..< numberOfTasks {

            expectations.append(self.expectation(withDescription: "semaphore block \(i)"))
        }

        let queue = GCDQueue.createConcurrent("testGCDSemaphore.queue")
        queue.apply(numberOfTasks) { (iteration: UInt) -> Void in

            XCTAssertTrue(queue.isCurrentExecutionContext())
            expectations[Int(iteration)].fulfill()
            _ = semaphore.signal()
        }

        semaphore.wait()

        self.waitForExpectations(withTimeout: 0.0, handler: nil)
    }

    func testGCDTimer() {

        var runningExpectations = [XCTestExpectation]()
        let numberOfTicksToTest = 10
        for i in 0..<numberOfTicksToTest {

            runningExpectations.append(self.expectation(withDescription: "timer tick \(i)"))
        }
        let suspendExpectation = self.expectation(withDescription: "timer suspended")

        var previousTimestamp = CFAbsoluteTimeGetCurrent()
        var iteration = 0
        let timer = GCDTimer.createAutoStart(.default, interval: DispatchTimeInterval.seconds(iteration + 1)) { (timer) -> Void in

            XCTAssertTrue(GCDQueue.default.isCurrentExecutionContext())

            let currentTimestamp = CFAbsoluteTimeGetCurrent()
            let elapsed = currentTimestamp - previousTimestamp
            let expected = Double(iteration + 1)
            XCTAssertGreaterThanOrEqual(elapsed + Double(0.001), expected, "Timer fired before expected time")
            XCTAssertTrue(timer.isRunning, "Timer's isRunning property is not true")

            if Int(iteration) < runningExpectations.count {

                runningExpectations[Int(iteration)].fulfill()
            }
            else {

                timer.suspend()
                XCTAssertFalse(timer.isRunning, "Timer's isRunning property is not false")
                suspendExpectation.fulfill()
            }
            
            iteration += 1
            
            previousTimestamp = CFAbsoluteTimeGetCurrent()
            timer.setTimer(DispatchTimeInterval.seconds(iteration + 1))
        }
        XCTAssertTrue(timer.isRunning, "Timer's isRunning property is not true")
        
        let numberOfTicks = TimeInterval(numberOfTicksToTest) + 1
        self.waitForExpectations(withTimeout: (numberOfTicks * (numberOfTicks / 2.0 + 1.0)) + 20.0, handler: nil)
    }
}
