import AVFoundation

/// 연결 가능한 오디오 입력 장치 목록을 반환
func listInputs() throws -> [AudioInputDevice] {
    var devices: [AudioInputDevice] = []

    // 실제 입력 가능한 장치 ID 목록 가져오기
    listPhysicalAudioInputDeviceIDs().forEach { deviceID in
        // 장치의 UID와 이름을 가져와서 Device로 구성
        if let uid = getDeviceUID(deviceID), let name = getDeviceName(deviceID) {
            devices.append(AudioInputDevice(id: uid, label: name))
        }
    }

    return devices
}

/// 실제로 오디오 입력 기능이 가능한 장치들의 AudioDeviceID 목록을 반환
func listPhysicalAudioInputDeviceIDs() -> [AudioDeviceID] {
    var propertySize: UInt32 = 0
    var status: OSStatus

    // macOS 시스템의 모든 오디오 장치 목록 가져오기
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    status = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &propertySize
    )
    guard status == noErr else { return [] }

    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

    status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &propertySize,
        &deviceIDs
    )
    guard status == noErr else { return [] }

    var inputDevices: [AudioDeviceID] = []

    for deviceID in deviceIDs {
        // 해당 장치에 입력 채널이 있는지 확인
        var streamConfigSize: UInt32 = 0
        var inputStreamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        status = AudioObjectGetPropertyDataSize(
            deviceID,
            &inputStreamAddress,
            0,
            nil,
            &streamConfigSize
        )
        if status != noErr { continue }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() } // 메모리 누수 방지

        status = AudioObjectGetPropertyData(
            deviceID,
            &inputStreamAddress,
            0,
            nil,
            &streamConfigSize,
            bufferList
        )
        if status != noErr { continue }

        // Swift에서 안전하게 AudioBufferList를 접근하는 방식
        let audioBufferList = UnsafeMutableAudioBufferListPointer(bufferList)
        let totalChannels = audioBufferList.reduce(0) { $0 + Int($1.mNumberChannels) }

        // 입력 채널이 없는 장치는 제외
        if totalChannels == 0 {
            continue
        }

        // USB 또는 내장 장치인지 확인 (블루투스, 네트워크 장치는 제외)
        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        status = AudioObjectGetPropertyData(
            deviceID,
            &transportAddress,
            0,
            nil,
            &transportSize,
            &transportType
        )
        if status != noErr { continue }

        if transportType == kAudioDeviceTransportTypeUSB || transportType == kAudioDeviceTransportTypeBuiltIn {
            inputDevices.append(deviceID)
        }
    }

    return inputDevices
}

/// 주어진 Device ID에 해당하는 AVCaptureDeviceInput 반환
/// 해당하는 device가 없으면 기본 오디오 입력 장치 반환
func getInputDevice(device: AudioInputDevice?) throws -> AVCaptureDeviceInput? {
    if let device = device {
        // 최신 macOS 방식: DiscoverySession을 사용해 장치 검색
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )

        let matched = discoverySession.devices.first(where: { $0.uniqueID == device.id })

        if let matched = matched {
            return try AVCaptureDeviceInput(device: matched)
        }
        return nil
    } else {
        // 기본 입력 장치를 반환
        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            return try AVCaptureDeviceInput(device: defaultDevice)
        }
        return nil
    }
}

/// UID 문자열로 AudioDeviceID를 찾는다
func getAudioDeviceIDFromUID(uid: String) -> AudioDeviceID? {
    var propertySize: UInt32 = 0
    var status: OSStatus = noErr

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

    for deviceID in deviceIDs {
        // 일부 앱은 UID 대신 ID 숫자 문자열을 넘기기도 함
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

        if let deviceUID = deviceUID?.takeRetainedValue() as String?, uid == deviceUID {
            return deviceID
        }
    }

    return nil
}

/// AudioDeviceID로부터 UID 문자열을 가져옴
func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var cfStr: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<CFString>.size)

    let status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0,
        nil,
        &size,
        &cfStr
    )

    if status == noErr, let str = cfStr?.takeRetainedValue() {
        return str as String
    }

    return nil
}

/// AudioDeviceID로부터 사용자 친화적인 장치 이름을 가져옴
func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var cfStr: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<CFString>.size)

    let status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0,
        nil,
        &size,
        &cfStr
    )

    if status == noErr, let str = cfStr?.takeRetainedValue() {
        return str as String
    }

    return nil
}