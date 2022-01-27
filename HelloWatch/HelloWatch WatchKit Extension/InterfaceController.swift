//
//  InterfaceController.swift
//  HelloWatch WatchKit Extension
//
//  Created by WuLei on 2021/11/16.
//

import WatchKit
import Foundation
import CoreMotion
import HealthKit

class InterfaceController: WKInterfaceController, HKWorkoutSessionDelegate {

  @IBOutlet weak var startButton: WKInterfaceButton!
  @IBOutlet weak var descText: WKInterfaceLabel!
  
  private let healthStore = HKHealthStore()
  private let motionManager = CMMotionManager()
  private var workoutSession: HKWorkoutSession!
  private let workoutConfiguration = HKWorkoutConfiguration()
  
  private let updateInterval = 1.0 / 60.0 // 60 Hz
  private var recording = false;
  private var timer: Timer?
  
  override func awake(withContext context: Any?) {
    // Configure interface objects here.
    print("healthDataAvailable: \(HKHealthStore.isHealthDataAvailable())")
    motionManager.accelerometerUpdateInterval = updateInterval
    workoutConfiguration.activityType = .golf
    workoutConfiguration.locationType = .outdoor
    
    updateDescText(nil)
  }
  
  override func willActivate() {
    // This method is called when watch view controller is about to be visible to user
  }
  
  override func didDeactivate() {
    // This method is called when watch view controller is no longer visible
  }
  
  @IBAction func onStartButtonClicked() {
    if recording {
      // stop updates
      timer?.invalidate()
      timer = nil
      motionManager.stopAccelerometerUpdates()
      workoutSession.stopActivity(with: Date())
      workoutSession.end()
      startButton.setTitle("Start")
    } else {
      // start updates
      motionManager.startAccelerometerUpdates()
      timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) {_ in
        if let accelerometerData = self.motionManager.accelerometerData {
          print("acceleration - x: \(accelerometerData.acceleration.x), y: \(accelerometerData.acceleration.y), z: \(accelerometerData.acceleration.z)")
  //        DispatchQueue.main.async {
  //          self.updateDescText(accelerometerData)
  //        }
        }
      }
      let date = Date()
      workoutSession = try! HKWorkoutSession(healthStore: healthStore, configuration: workoutConfiguration)
      workoutSession.delegate = self
      workoutSession.startActivity(with: date)
      startButton.setTitle("Stop")
    }
    recording = !recording;
  }
  
  func updateDescText(_ accelerometerData: CMAccelerometerData?) {
    if let data = accelerometerData {
      descText.setText("x:\(data.acceleration.x)\ny:\(data.acceleration.y)\nz:\(data.acceleration.z)")
    } else {
      descText.setText("x:-\ny:-\nz:-")
    }
  }
  
  func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
    print("session state change to: \(toState.rawValue) from \(fromState.rawValue)")
  }
  
  func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    print("session error: \(error)")
  }
}
