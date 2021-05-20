//
//  PoseDetectorTests.swift
//  PoseDetectorTests
//
//  Created by WuLei on 2021/3/30.
//

import Vision
import XCTest
@testable import PoseDetector

class PoseDetectorTests: XCTestCase {
    
    private let analysisManager = SwingAnalysisManager.shared

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        let bundle = Bundle(for: type(of: self))
        guard let path = bundle.path(forResource: "testData", ofType: ".txt") else {
            XCTFail("test data not found")
            return
        }
        print("path: \(path)")
        let dataString = try String(contentsOfFile: path)
        let lines = dataString.split(separator: "\n")
        var frameJoints = [[String: DetectedPoint]]()
        var size = CGSize(width: 0, height: 0)
        var frameRate: Float = 0
        var jointFrame = 0
        let numberFormatter = NumberFormatter()
        var joints = [String: DetectedPoint]()
        for line in lines {
            if line.starts(with: "size:") {
                // size:(1080.0, 1920.0)
                var data = line
                data.removeFirst("size:(".count)
                data.removeLast()
                let sizeData = data.split(separator: ",")
                size.width = CGFloat(truncating: numberFormatter.number(from: String(sizeData[0]))!)
                size.height = CGFloat(truncating: numberFormatter.number(from: String(sizeData[1]))!)
            } else if line.starts(with: "frameRate:") {
                // frameRate:29.973026
                var data = line
                data.removeFirst("frameRate:".count)
                frameRate = Float(truncating: numberFormatter.number(from: String(data))!)
            } else if line.starts(with: "jointFrames:") {
                // jointFrames:1348
                var data = line
                data.removeFirst("jointFrames:".count)
                jointFrame = Int(truncating: numberFormatter.number(from: String(data))!)
            } else if line.starts(with: "{") {
                joints.removeAll()
            } else if line.starts(with: "}") {
                frameJoints.append(joints)
            } else if line.count > 0 {
                // {
                // right_foot_joint|(0.08051767945289612, 0.14792144298553467)
                // }
                var data = line.split(separator: "|")
                let jointName = String(data[0])
                data[1].removeFirst()
                data[1].removeLast()
                let locationData = data[1].split(separator: ",")
                let x = CGFloat(truncating: numberFormatter.number(from: String(locationData[0]))!)
                let y = CGFloat(truncating: numberFormatter.number(from: String(locationData[1]))!)
                let point = DetectedPoint(location: CGPoint(x: x, y: y), confidence: 1)
                joints[jointName] = point
            }
        }
        
        let detectedResult = DetectedResult(size: size, frameRate: frameRate, joints: frameJoints, jointFrames: jointFrame)
        print("size: \(detectedResult.size), frameRate: \(frameRate), jointFrames: \(jointFrame), jointsCount: \(frameJoints.count) \n")
        let result = analysisManager.getAnalyzedResult(detectedResult: detectedResult)
        print(result)
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
}
