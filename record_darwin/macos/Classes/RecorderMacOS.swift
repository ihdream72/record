import CoreAudio
import AVFoundation
import Foundation

func listInputs() throws -> [Device] {
  var devices: [Device] = []

//  listInputDevices().forEach { input in
//    devices.append(Device(id: input.uniqueID, label: input.localizedName))
//  }

  getAvailableMicrophones().forEach { input in
    devices.append(Device(id: input.id, label: input.name))
  }
  
  return devices
}

func listInputDevices() -> [AVCaptureDevice] {
  let discoverySession = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInMicrophone],
    mediaType: .audio, position: .unspecified
  )
  
  return discoverySession.devices
}

func getAvailableMicrophones() -> [(id: AudioDeviceID, name: String)] {
    var devices = [AudioDeviceID]()
    var propertySize = UInt32(0)

    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // 1. 먼저 오디오 장치 개수를 가져온다.
    var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
    guard status == noErr else { return [] }

    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    if deviceCount == 0 { return [] }

    // 2. 실제 오디오 장치 리스트를 가져온다.
    devices = [AudioDeviceID](repeating: 0, count: deviceCount)
    status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &devices)
    guard status == noErr else { return [] }

    var microphoneList = [(id: AudioDeviceID, name: String)]()

    for deviceID in devices {
        var deviceName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)

        var namePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // 3. 각 오디오 장치의 이름을 가져온다.
        status = AudioObjectGetPropertyData(deviceID, &namePropertyAddress, 0, nil, &nameSize, &deviceName)
        if status != noErr { continue }

        var inputChannels: UInt32 = 0
        var channelsSize = UInt32(MemoryLayout<UInt32>.size)

        var channelsPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        // 4. 입력 채널이 있는지 확인 (마이크인지 판별)
        status = AudioObjectGetPropertyDataSize(deviceID, &channelsPropertyAddress, 0, nil, &channelsSize)
        if status != noErr || channelsSize == 0 { continue }

        let isDuplicate = microphoneList.contains { $0.name == (deviceName as String) }
        if !isDuplicate {
            microphoneList.append((id: deviceID, name: deviceName as String))
        }
    }

    return microphoneList
}

func getInputDevice(device: Device?) throws -> AVCaptureDeviceInput? {
  guard let device = device else {
    // try to select default device
    let defaultDevice = AVCaptureDevice.default(for: .audio)
    guard let defaultDevice = defaultDevice else {
      return nil
    }
    
    return try AVCaptureDeviceInput(device: defaultDevice)
  }

  // find the given device
  let devs = listInputDevices()
  let captureDev = devs.first { dev in
    dev.uniqueID == device.id
  }
  guard let captureDev = captureDev else {
    return nil
  }
  
  return try AVCaptureDeviceInput(device: captureDev)
}

func getAudioDeviceIDFromUID(uid: String) -> AudioDeviceID? {
  var propertySize: UInt32 = 0
  var status: OSStatus = noErr
  
  // Get the number of devices
  var propertyAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  status = AudioObjectGetPropertyDataSize(
    AudioObjectID(kAudioObjectSystemObject),
    &propertyAddress,
    0,
    nil,
    &propertySize
  )
  if status != noErr {
    return nil
  }
  
  // Get the device IDs
  let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
  var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
  status = AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject),
    &propertyAddress,
    0,
    nil,
    &propertySize,
    &deviceIDs
  )
  if status != noErr {
    return nil
  }

  // Get device UID
  for deviceID in deviceIDs {

    // feat(macOS): Support device by deviceID as well as deviceUID
    // Support lookup by devicezID rather than uid
    if String(deviceID) == uid {
      return deviceID
    }


    propertyAddress.mSelector = kAudioDevicePropertyDeviceUID
    propertySize = UInt32(MemoryLayout<CFString>.size)
    var deviceUID: Unmanaged<CFString>?

    status = AudioObjectGetPropertyData(
      deviceID,
      &propertyAddress,
      0,
      nil,
      &propertySize,
      &deviceUID
    )
    if status == noErr && uid == deviceUID?.takeRetainedValue() as String? {
      return deviceID
    }
  }
  
  return nil
}
