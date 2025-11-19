//
//  i2c.swift
//
//  Adapted from: https://github.com/uraimo/SwiftyGPIO
//
//  Copyright © 2025 Nick Nallick. Licensed under the MIT License.
//
//  We expect each unique identifier provided by the i2c device driver to refer to a unique hardware bus.
//  Therefore, to avoid conflicts, only one I2CBus instance per device identifier should be created.
//  Thus, we provide an actor isolated context here to allow sharing of that instance between threads.
//

import Ci2c

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
import Darwin.C
#endif

#if canImport(FoundationExtensions)
import FoundationExtensions
#else
import Foundation
#endif

public actor I2CBus {

    private let deviceIdentifier: Int

    private var fileDescriptor: Int32 = -1
    private var slaveAddress = -1
    private let payloadLength = 32

    public init(device identifier: Int = 1) {
        self.deviceIdentifier = identifier
    }

    deinit {
        if fileDescriptor != -1 { close(fileDescriptor) }
    }

    public func isReachable(at address: Int) -> Bool {
        guard let _ = try? set(slaveAddress: address) else { return false }

        // Mimic the behaviour of i2cdetect, performing bogus read/quickwrite depending on the address
        let response: Int32
        switch address {
            case 0x3...0x2f:
                response = i2c_smbus_write_quick(fileDescriptor, 0)
            case 0x30...0x37:
                response = i2c_smbus_read_byte(fileDescriptor)
            case 0x38...0x4f:
                response = i2c_smbus_write_quick(fileDescriptor, 0)
            case 0x50...0x5f:
                response = i2c_smbus_read_byte(fileDescriptor)
            case 0x60...0x77:
                response = i2c_smbus_write_quick(fileDescriptor, 0)
            default:
                response = i2c_smbus_read_byte(fileDescriptor)
        }

        return response >= 0
    }

    public func read(from address: Int) throws -> UInt8 {
        try set(slaveAddress: address)
        let result = i2c_smbus_read_byte(fileDescriptor)
        guard result >= 0 else { throw Failure(.read, detail: "I2C read byte failed") }
        return UInt8(truncatingIfNeeded: result)
    }

    public func read(from address: Int, command: UInt8) throws -> UInt8 {
        try set(slaveAddress: address)
        let result = i2c_smbus_read_byte_data(fileDescriptor, command)
        guard result >= 0 else { throw Failure(.read, detail: "I2C read byte data failed") }
        return UInt8(truncatingIfNeeded: result)
    }

    public func readInt16(from address: Int, command: UInt8) throws -> Int16 {
        Int16(bitPattern: try readUInt16(from: address, command: command))
    }

    public func readUInt16(from address: Int, command: UInt8) throws -> UInt16 {
        try set(slaveAddress: address)
        let result = i2c_smbus_read_word_data(fileDescriptor, command)
        guard result >= 0 else { throw Failure(.read, detail: "I2C read word failed") }
        return UInt16(truncatingIfNeeded: result)
    }

    public func readInt24(from address: Int, command: UInt8) throws -> Int32 {
        var data = Data(repeating: 0, count: 4)
        data[3] = try read(from: address, command: command)
        data[2] = try read(from: address)
        data[1] = try read(from: address)
        return unsafe data.withUnsafeBytes({ unsafe $0.bindMemory(to: Int32.self).baseAddress?.pointee })! >> 8
    }

    public func readUInt24(from address: Int, command: UInt8) throws -> UInt32 {
        var data = Data(repeating: 0, count: 4)
        data[3] = try read(from: address, command: command)
        data[2] = try read(from: address)
        data[1] = try read(from: address)
        return unsafe data.withUnsafeBytes({ unsafe $0.bindMemory(to: UInt32.self).baseAddress?.pointee })! >> 8
    }

    public func readBlock(from address: Int, command: UInt8) throws -> [UInt8] {
        try set(slaveAddress: address)
        var buffer = [UInt8](repeating: 0, count: payloadLength)
        guard unsafe i2c_smbus_read_block_data(fileDescriptor, command, &buffer) >= 0 else { throw Failure(.read, detail: "I2C read block failed") }
        return buffer
    }

    public func readI2CBlock(from address: Int, command: UInt8) throws -> [UInt8] {
        try set(slaveAddress: address)
        var buffer = [UInt8](repeating: 0, count: payloadLength)
        guard unsafe i2c_smbus_read_i2c_block_data(fileDescriptor, command, UInt8(payloadLength), &buffer) >= 0 else { throw Failure(.read, detail: "I2C read i2c block failed") }
        return buffer
    }

    public func write(to address: Int, value: UInt8) throws {
        try set(slaveAddress: address)
        guard i2c_smbus_write_byte(fileDescriptor, value) >= 0 else { throw Failure(.write, detail: "I2C write byte failed") }
    }

    public func write(to address: Int, command: UInt8, value: UInt8) throws {
        try set(slaveAddress: address)
        guard i2c_smbus_write_byte_data(fileDescriptor, command, value) >= 0 else { throw Failure(.write, detail: "I2C write byte data failed") }
    }

    public func writeQuick(to address: Int, value: UInt8) throws {
        try set(slaveAddress: address)
        guard i2c_smbus_write_quick(fileDescriptor, value) >= 0 else { throw Failure(.write, detail: "I2C write quick failed") }
    }

    public func writeUInt16(to address: Int, command: UInt8, value: UInt16) throws {
        try set(slaveAddress: address)
        guard i2c_smbus_write_word_data(fileDescriptor, command, value) >= 0 else { throw Failure(.write, detail: "I2C write word failed") }
    }

    public func writeBlock(to address: Int, command: UInt8, values: [UInt8]) throws {
        try set(slaveAddress: address)
        guard unsafe i2c_smbus_write_block_data(fileDescriptor, command, UInt8(values.count), values) >= 0 else { throw Failure(.write, detail: "I2C write block failed") }
    }

    public func writeI2CBlock(to address: Int, command: UInt8, values: [UInt8]) throws {
        try set(slaveAddress: address)
        guard unsafe i2c_smbus_write_i2c_block_data(fileDescriptor, command, UInt8(values.count), values) >= 0 else { throw Failure(.write, detail: "I2C write i2c block failed") }
    }

    public func set(pec address: Int, enabled: Bool) throws {
        try set(slaveAddress: address)
        let I2C_PEC: UInt = 0x708
        guard ioctl(fileDescriptor, I2C_PEC, enabled ? 1 : 0) == 0 else { throw Failure(.ioControl, detail: "I2C failed to set PEC") }
    }

    private func set(slaveAddress: Int) throws {
        if fileDescriptor <= 0 {
            let fileDescriptor = unsafe open("/dev/i2c-\(deviceIdentifier)", O_RDWR)
            guard fileDescriptor > 0 else { throw Failure(.open, detail: "Couldn't open the I2C device \(deviceIdentifier)") }
            self.fileDescriptor = fileDescriptor
        }

        guard self.slaveAddress != slaveAddress else { return }
        let I2C_SLAVE_FORCE: UInt = 0x706
        guard ioctl(fileDescriptor, I2C_SLAVE_FORCE, CInt(slaveAddress)) == 0 else { throw Failure(.ioControl, detail: "I2C failed to set slave address") }
        self.slaveAddress = slaveAddress
    }

    /// Perform an operation with this isolation context, allowing multiple calls to this i2c bus context using a single await.
    ///
    /// - Parameter operation: The closure to perform in isolation.
    ///
    /// - Throws: Any errors generated by the operation.
    ///
    /// For example:
    ///
    ///     let i2cBus = I2CBus()
    ///     let sum: Int = try await i2cBus.withIsolatedContext { context in
    ///         let b1 = try context.read(from: 0x11)
    ///         let b2 = try context.read(from: 0x11)
    ///         return Int(b1) + Int(b2)
    ///     }
    ///
    public func withIsolatedContext<Result: Sendable>(_ operation: @Sendable (_ context: isolated I2CBus) throws -> Result) throws -> Result {
        try operation(self)
    }
}


//  Adapted from: https://github.com/uraimo/SwiftyGPIO
//
//  https://github.com/uraimo/SwiftyGPIO/blob/master/Sources/I2C.swift
//
//  SwiftyGPIO
//
//  Copyright (c) 2017 Umberto Raimondi
//  Licensed under the MIT license, as follows:
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
//  SOFTWARE.)
