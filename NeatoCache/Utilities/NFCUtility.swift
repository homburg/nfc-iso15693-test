/// Copyright (c) 2020 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import Foundation

import CoreNFC

typealias NFCReadingCompletion = (Result<NFCNDEFMessage?, Error>) -> Void
typealias LocationReadingCompletion = (Result<Location, Error>) -> Void

enum NFCError: LocalizedError {
  case unavailable
  case invalidated(message: String)
  case invalidPayloadSize

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "NFC Reader Not Available"
    case let .invalidated(message):
      return message
    case .invalidPayloadSize:
      return "NDEF payload size exceeds the tag limit"
    }
  }
}

class NFCUtility: NSObject {
  private var session: NFCTagReaderSession?
  private var completion: LocationReadingCompletion?
  
  static func performAction(
    completion: LocationReadingCompletion? = nil
  ) {
    debugPrint("Perform action")
    
    // 3
    guard NFCTagReaderSession.readingAvailable else {
      completion?(.failure(NFCError.unavailable))
      print("NFC is not available on this device")
      return
    }

    // shared.action = action
    shared.completion = completion
    
    // 4
    shared.session = NFCTagReaderSession(
      pollingOption: .iso15693,
      delegate: shared.self,
      queue: nil)
    // 5
    // shared.session?.alertMessage = action.alertMessage
    // 6
    shared.session?.begin()
  }

  enum NFCAction {
    case readLocation
    case setupLocation(locationName: String)
    case addVisitor(visitorName: String)

    var alertMessage: String {
      switch self {
      case .readLocation:
        return "Place tag near iPhone to read the location."
      case .setupLocation(let locationName):
        return "Place tag near iPhone to setup \(locationName)"
      case .addVisitor(let visitorName):
        return "Place tag near iPhone to add \(visitorName)"
      }
    }
    
    
  }

  private static let shared = NFCUtility()
  // private var action: NFCAction = .readLocation
}

// MARK: - NFC Tag Reader Session Delegate
extension NFCUtility: NFCTagReaderSessionDelegate {
  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    // Not used
  }
  
  
  func tagReaderSession(
    _ session: NFCTagReaderSession,
    didDetect tags: [NFCTag]
  ) {
    print("tagReaderSession")
    
    let vTags = tags.filter() { t in
      switch (t) {
      case .iso15693(_):
        return true;
      default:
        return false;
      }
    }
    
    guard
      let tag = vTags.first,
      vTags.count == 1
      else {
        session.alertMessage = """
          There are too many tags present. Remove all and then try again.
          """
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
          session.restartPolling()
        }
        return
    }
    
    print("One tag")
    dump(tag)
    
    // 1
    session.connect(to: tag) { error in
      print("Connected!")
      
      if let error = error {
        print("Handling connection error")
        self.handleError(error)
        return
      }
      
      guard case let .iso15693(v) = tag else {
        print("Not iso15693 tag!, ignore!")
        return;
      }
      
      let mfgCode = String(format: "%02X", v.icManufacturerCode)
      let uid = format(data: v.identifier)
      let serial = format(data: v.icSerialNumber)
      dump(uid)
      dump(serial)
      
      
      session.alertMessage = "\(mfgCode) \(uid) \(serial)"
      
      if #available(iOS 14, *) {
        let flags: NFCISO15693RequestFlag = [.highDataRate, .protocolExtension, .option]
        
        // v.readNDEF() {
        //   print($0, $1)
        // }
        
        let params: Data = Data([])
        print(String(describing: flags))
        print(String(describing: params))
        
        // Not allowed for reserved command codes
        // v.customCommand(requestFlags: flags, customCommandCode: 0x20, customRequestParameters: params) {
        //   print($0)
        // }
        
        // Fails
        v.readSingleBlock(requestFlags: flags, blockNumber: 20) {
          print($0)
        }
        
        // Fails
        // v.readMultipleBlocks(requestFlags: flags, blockRange: NSRange(0...4)) {
        //   print($0)
        // }
      }

      
      session.invalidate()
     
    }

  }
  
  private func handleError(_ error: Error) {
    debugPrint(error.localizedDescription)
    session?.alertMessage = error.localizedDescription
    session?.invalidate()
  }
  
  func tagReaderSession(
    _ session: NFCTagReaderSession,
    didInvalidateWithError error: Error
  ) {
    print("didInvalidateWithError")
    if let error = error as? NFCReaderError,
        error.code != .readerSessionInvalidationErrorUserCanceled {
      completion?(.failure(NFCError.invalidated(message:
        error.localizedDescription)))
    }

    self.session = nil
    completion = nil
  }
}

fileprivate func format(data: Data) -> String {
  return data.reduce("") { acc, item in
    return acc + String(format: "%02X", item)
  }
}
