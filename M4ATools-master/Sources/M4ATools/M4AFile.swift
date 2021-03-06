//
//  M4AFile.swift
//  M4ATools
//
//  Created by Andrew Hyatt on 2/8/18.
//  Copyright © 2018 Andrew Hyatt. All rights reserved.
//

import Foundation

/// Editable representation of a M4A audio file
///
/// - Author: Andrew Hyatt <ahyattdev@icloud.com>
/// - Copyright: Copyright © 2018 Andrew Hyatt
open class M4AFile {
        
    /// M4A file related errors
    public enum M4AFileError: Error {
        
        /// When a block of an unknown type is loaded
        case invalidBlockType
        /// When a file is not valid M4A
        case invalidFile
        
    }
        
    /// Used to check if a block is recognized
    private static let validTypes = ["ftyp", "mdat", "moov", "pnot", "udta",
                                     "uuid", "moof", "free",  "skip", "jP2 ",
                                     "wide", "load", "ctab", "imap", "matt",
                                     "kmat", "clip", "crgn", "sync", "chap",
                                     "tmcd", "scpt", "ssrc", "PICT"]
    
    /// The `Block`s in the M4A file
    internal var blocks: [Block]
    
    /// Used to get the metadata block
    internal var metadataBlock: Block? {
        return findBlock(["moov", "udta", "meta", "ilst"])
    }
    
    /// The name of the file, if created from a URL or otherwise set
    open var fileName: "C:\Users\honglab\Desktop\PROGRAM\Swift\M4ATools-master\audio\20200922 205259.m4a"
    
    /// The URL the file was loaded from
    ///
    /// If loaded from data this is nil
    open var url: nil
    
    /// Creates an instance from data
    /// - parameters:
    ///   - data: The data of an M4A file
    /// - throws: `M4AFileError.invalidBlockType`
    public init(data: Data) throws {
        blocks = [Block]()
        
        guard data.count >= 8 else {
            throw M4AFileError.invalidFile
        }
        
        // Begin reading file
        var index = data.startIndex
        while (index != data.endIndex) {
            // Offset 0 to 4
            let sizeData = data.subdata(in: index ..< index.advanced(by: 4))
            // Offset 4 to 8
            let typeData = data.subdata(in: index.advanced(by: 4)
                ..< index.advanced(by: 8))
            
            // Turn size into an integer
            var size = Int(UInt32(bigEndian:
                sizeData.withUnsafeBytes { $0.pointee }))
            
            let type = String(data: typeData, encoding: .macOSRoman)!
            
            guard typeIsValid(type) else {
                throw M4AFileError.invalidBlockType
            }
            
            var largeSize = false
            if size == 1 && type == "mdat" {
                largeSize = true
                // mdat sometimes has a size of 1 and
                // it's size is 12 bytes into itself
                let mdatSizeData = data.subdata(in: index.advanced(by: 12)
                    ..< index.advanced(by: 16))
                size = Int(UInt32(bigEndian:
                    mdatSizeData.withUnsafeBytes { $0.pointee }))
            }
            
            // Load block
            let blockContents = data.subdata(in: index.advanced(by: 8)
                ..< index.advanced(by: size))
            
            index = index.advanced(by: size)
            
            let block = Block(type: type, data: blockContents, parent: nil)
            block.largeAtomSize = largeSize
            
            blocks.append(block)
        }
        
        // See if loaded metadata identifiers are recognized
        if let meta = metadataBlock {
            for block in meta.children {
                if Metadata.StringMetadata(rawValue: block.type) == nil &&
                    Metadata.UInt8Metadata(rawValue: block.type) == nil &&
                    Metadata.UInt16Metadata(rawValue: block.type) == nil &&
                    Metadata.UInt32Metadata(rawValue: block.type) == nil &&
                    Metadata.UInt64Metadata(rawValue: block.type) == nil &&
                    Metadata.TwoIntMetadata(rawValue: block.type) == nil &&
                    Metadata.ImageMetadata(rawValue: block.type) == nil
                    {
                        print("Unrecognized metadata type: " + block.type)
                }
            }
        }
    }
    
    /// Initizlizes `M4AFile` from a `URL`
    ///
    /// - parameters:
    ///   - url: The `URL` of an M4A file
    ///
    /// - throws: What `init(data:)` throws
    public convenience init(url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(data: data)
        fileName = url.pathComponents.last
        self.url = url
    }
    
    /// Outputs an M4A file
    ///
    /// - parameters:
    ///   - url: The `URL` to write the file to
    ///
    /// - throws: What `Data.write(to:)` throws
    open func write(url: URL) throws {
        var data = Data()
        for block in blocks {
            data = block.write(data)
        }
        
        try data.write(to: url)
    }
    
    /// Generates the data of an M4A file
    ///
    /// - returns: `Data` of the file
    open func write() -> Data {
        var data = Data()
        for block in blocks {
            data = block.write(data)
        }
        return data
    }
    
    /// Retrieves metadata of the `String` type
    ///
    /// - parameters:
    ///   - metadata: The metadtata type
    ///
    /// - returns: A `String` if the requested key exists
    open func getStringMetadata(_ metadata: Metadata.StringMetadata)
        -> String? {
        guard let metadataContainerBlock = self.metadataBlock else {
            return nil
        }
        
        let type = metadata.rawValue
        
        guard let metaBlock = M4AFile.getMetadataBlock(metadataContainer:
            metadataContainerBlock, name: type) else {
                return nil
        }
        
        guard let data = M4AFile.readMetadata(metadata: metaBlock) else {
            return nil
        }
        
        return String(bytes: data, encoding: .utf8)
    }
    
    /// Retrieves metadata of the `UInt8` type
    ///
    /// - parameters:
    ///   - metadata: The metadtata type
    ///
    /// - returns: A `UInt8` if the requested key exists
    open func getUInt8Metadata(_ metadata: Metadata.UInt8Metadata) -> UInt8? {
        if let metadataChild = getMetadataBlock(type: metadata.rawValue) {
            guard metadataChild.data.count == 9 else {
                print("UInt8 metadata should have 1 byte of data!")
                return nil
            }
            return UInt8(metadataChild.data[8])
        } else {
            return nil
        }
    }
    
    /// Retrieves metadata of the `UInt16` type
    ///
    /// - Parameter metadata: The metadata type
    /// - Returns: A `UInt16` value of the requested key exists
    open func getUInt16Metadata(_ metadata: Metadata.UInt16Metadata) -> UInt16? {
        if let metadataChild = getMetadataBlock(type: metadata.rawValue) {
            guard metadataChild.data.count == 10 else {
                print("UInt16 metadata should have 2 bytes of data!")
                return nil
            }
            let data = [metadataChild.data[9], metadataChild.data[8]]
            let uint16 = UnsafePointer(data).withMemoryRebound(to: UInt16.self, capacity: 1) {
                $0.pointee
            }
            return uint16
        } else {
            return nil
        }
    }
    
    /// Retrieves metadata of the `UInt32` type
    ///
    /// - Parameter metadata: The metadata type
    /// - Returns: A `UInt32` value of the requested key exists
    open func getUInt32Metadata(_ metadata: Metadata.UInt16Metadata) -> UInt32? {
        if let metadataChild = getMetadataBlock(type: metadata.rawValue) {
            guard metadataChild.data.count == 12 else {
                print("UInt32 metadata should have 4 bytes of data!")
                return nil
            }
            let data = [metadataChild.data[11], metadataChild.data[10], metadataChild.data[9], metadataChild.data[8]]
            let uint32 = UnsafePointer(data).withMemoryRebound(to: UInt32.self, capacity: 1) {
                $0.pointee
            }
            return uint32
        } else {
            return nil
        }
    }
    
    /// Retrieves metadata of the `UInt64` type
    ///
    /// - Parameter metadata: The metadata type
    /// - Returns: A `UInt64` value of the requested key exists
    open func getUInt64Metadata(_ metadata: Metadata.UInt16Metadata) -> UInt64? {
        if let metadataChild = getMetadataBlock(type: metadata.rawValue) {
            guard metadataChild.data.count == 16 else {
                print("UInt64 metadata should have 8 bytes of data!")
                return nil
            }
            var data = [metadataChild.data[15],
                        metadataChild.data[14],
                        metadataChild.data[13],
                        metadataChild.data[12]
            ]
            
            data += [metadataChild.data[11],
                     metadataChild.data[10],
                     metadataChild.data[9],
                     metadataChild.data[8]
            ]
            
            let uint64 = UnsafePointer(data).withMemoryRebound(to: UInt64.self, capacity: 1) {
                $0.pointee
            }
            return uint64
        } else {
            return nil
        }
    }
    
    /// Retrieves metadata consisting of two unsigned 16-bit integers
    ///
    /// - parameters:
    ///   - metadata: The metadtata type
    ///
    /// - returns: A tuple consisting of two 16 bit unsigned integers
    open func getTwoIntMetadata(_ metadata: Metadata.TwoIntMetadata)
        -> (UInt16, UInt16)? {
            if let metadataChild = getMetadataBlock(type: metadata.rawValue) {
                guard metadataChild.data.count == 16 else {
                    print("Invalid two int metadata read attempted.")
                    return nil
                }
                let data = metadataChild.data
                let firstIntData =
                    data[data.startIndex.advanced(by: 10) ..<
                    data.startIndex.advanced(by: 12)]
                let secondIntData =
                    data[data.startIndex.advanced(by: 12) ..<
                    data.startIndex.advanced(by: 14)]
                
                // We are casting back to UInt16 because UInt16 doesn't have a
                // way to do this
                let firstInt =
                    (firstIntData.withUnsafeBytes({ $0.pointee }) as UInt16)
                        .bigEndian

                let secondInt: UInt16 =
                    (secondIntData.withUnsafeBytes({ $0.pointee }) as UInt16)
                        .bigEndian
                
                return (firstInt, secondInt)
            } else {
                return nil
            }
    }
    
    /// Sets a `String` metadata key
    ///
    /// - parameters:
    ///   - metadata: The metadtata type
    ///   - value: The `String` to set the key to
    open func setStringMetadata(_ metadata: Metadata.StringMetadata,
                                  value: String) {
        // Get data to write to the metadata block
        var data = ByteBlocks.stringIdentifier
        guard let stringData = value.data(using: .utf8) else {
            print("Invalid UTF-8 string given.")
            return
        }
        data += stringData
        
        // Write the data if the block exists, create block if it doesn't
        if let block = getMetadataBlock(type: metadata.rawValue) {
            block.data = Data(data)
        } else {
            // The block doesn't exist, we need to create it
            var metadataContainer: Block! = metadataBlock
            if metadataContainer == nil {
                // Create the metadata block
                print("TODO: Create metadata block")
                metadataContainer = nil
            }
            
            data = "data".data(using: .macOSRoman)! + data
            
            var size = UInt32(data.count + 4).bigEndian
            let sizeData = Data(bytes: &size, count:
                MemoryLayout.size(ofValue: size))
            data = sizeData + data
            let block = Block(type: metadata.rawValue, data: Data(data),
                              parent: metadataContainer)
            metadataContainer.children.append(block)
        }
    }
    
    /// Sets metadata of the type `UInt8`
    ///
    /// - parameters:
    ///   - metadata: The metadtata type
    ///   - value: The `UInt8` value to set the metadata to
    open func setUInt8Metadata(_ metadata: Metadata.UInt8Metadata, value: UInt8) {
        var bigEndian = value.bigEndian
        let data = Data(buffer: UnsafeBufferPointer(start: &bigEndian, count: 1))
        write(intData: data, blockType: metadata.rawValue)
    }
    
    /// Sets metadata of the type `UInt16`
    ///
    /// - Parameters:
    ///   - metadata: The metadata type
    ///   - value: The `UInt16` value to set the metadata to
    open func setUInt16Metadata(_ metadata: Metadata.UInt16Metadata, value: UInt16) {
        var bigEndian = value.bigEndian
        let data = Data(buffer: UnsafeBufferPointer(start: &bigEndian, count: 1))
        write(intData: data, blockType: metadata.rawValue)
    }
    
    /// Sets metadata of the type `UInt32`
    ///
    /// - Parameters:
    ///   - metadata: The metadata type
    ///   - value: The `UInt32` value to set the metadata to
    open func setUInt32Metadata(_ metadata: Metadata.UInt32Metadata, value: UInt32) {
        var bigEndian = value.bigEndian
        let data = Data(buffer: UnsafeBufferPointer(start: &bigEndian, count: 1))
        write(intData: data, blockType: metadata.rawValue)
    }
    
    /// Sets metadata of the type `UInt64`
    ///
    /// - Parameters:
    ///   - metadata: The metadata type
    ///   - value: The `UInt64` value to set the metadata to
    open func setUInt64Metadata(_ metadata: Metadata.UInt64Metadata, value: UInt64) {
        var bigEndian = value.bigEndian
        let data = Data(buffer: UnsafeBufferPointer(start: &bigEndian, count: 1))
        write(intData: data, blockType: metadata.rawValue)
    }
    
    
    /// Write data as integer metadata
    ///
    /// - Parameters:
    ///   - intData: The integer metadata
    ///   - blockType: The block type identifier as `String`
    internal func write(intData: Data, blockType: String) {
        // Get data to write to the metadata block
        var data = ByteBlocks.intIdentifier
        
        // Write the value
        data += intData[intData.startIndex ..< intData.endIndex]
        
        if let block = getMetadataBlock(type: blockType) {
            // The block exists, just give it new data
            block.data = Data(data)
        } else {
            // The block doesn't exist, we need to create it
            var metadataContainer: Block! = metadataBlock
            if metadataContainer == nil {
                // Create the metadata block
                print("TODO: Create metadata block")
                metadataContainer = nil
            }
            
            data = "data".data(using: .macOSRoman)! + data
            
            var size = UInt32(data.count + 4).bigEndian
            let sizeData = Data(bytes: &size, count:
                MemoryLayout.size(ofValue: size))
            data = sizeData + data
            let block = Block(type: blockType, data: Data(data),
                              parent: metadataContainer)
            metadataContainer.children.append(block)
        }
    }
    
    /// Sets a two int metadata key
    ///
    /// - parameters:
    ///   - metadata: The metadtata type
    ///   - value: The value to set the key to
    open func setTwoIntMetadata(_ metadata: Metadata.TwoIntMetadata,
                                  value: (UInt16, UInt16)) {
        // Get data to write to the metadata block
        var data = ByteBlocks.eightEmptyBytes
        
        var firstInt = value.0.bigEndian
        var secondInt = value.1.bigEndian
        // Write the value
        data += ByteBlocks.twoEmptyBytes
        data += Data(buffer: UnsafeBufferPointer(start: &firstInt, count: 1))
        data += Data(buffer: UnsafeBufferPointer(start: &secondInt, count: 1))
        data += ByteBlocks.twoEmptyBytes
        
        if let block = getMetadataBlock(type: metadata.rawValue) {
            // The block exists, just give it new data
            block.data = Data(data)
        } else {
            // The block doesn't exist, we need to create it
            var metadataContainer: Block! = metadataBlock
            if metadataContainer == nil {
                // Create the metadata block
                print("TODO: Create metadata block")
                metadataContainer = nil
            }
            
            data = "data".data(using: .macOSRoman)! + data
            
            var size = UInt32(data.count + 4).bigEndian
            let sizeData = Data(bytes: &size, count:
                MemoryLayout.size(ofValue: size))
            data = sizeData + data
            let block = Block(type: metadata.rawValue, data: Data(data),
                              parent: metadataContainer)
            metadataContainer.children.append(block)
        }
    }
    
    /// Gets a metadata block from the metadata container
    ///
    /// - parameters:
    ///   - metadataContainer: Contains all metadata blocks
    ///   - name: The name of the block to get
    ///
    /// - returns: The metadata block if found
    private static func getMetadataBlock(metadataContainer: Block, name: String)
        -> Block? {
        for block in metadataContainer.children {
            if block.type == name {
                return block
            }
        }
        return nil
    }
    
    /// Turns a metadata block into `Data`
    ///
    /// - parameters:
    ///   - metadata: The metadata to read
    ///
    /// - returns: `Data` if the metadata block is valid
    private static func readMetadata(metadata: Block) -> Data? {
        var data = metadata.data
        let sizeData = data[data.startIndex ..< data.startIndex.advanced(by: 4)]
        let typeData = data[data.startIndex.advanced(by: 4)
            ..< data.startIndex.advanced(by: 8)]
        let shouldBeNullData = data[data.startIndex.advanced(by: 8)
            ..< data.startIndex.advanced(by: 16)]
        data = data.advanced(by: sizeData.count + typeData.count
            + shouldBeNullData.count)
        
        let size = Int(UInt32(bigEndian:
            sizeData.withUnsafeBytes { $0.pointee }))
        guard let type = String(bytes: typeData, encoding: .macOSRoman),
            type == "data" else {
            print("Could not get metadata entry type")
            return nil
        }
        
        guard shouldBeNullData.elementsEqual(ByteBlocks.stringIdentifier) ||
            shouldBeNullData.elementsEqual(ByteBlocks.intIdentifier) else {
                print("Invalid metadata entry block " + metadata.type)
            return nil
        }
        
        guard size == shouldBeNullData.count + typeData.count + sizeData.count
            + data.count else {
            print("Invalid metadata entry block " + metadata.type)
            return nil
        }
        
        return data
    }
    
    /// Gets a metadata block when givena type
    /// - parameters:
    ///   - type: Metadata type name.
    /// - returns:
    /// The child block inside the metadata block, not the parent block.
    private func getMetadataBlock(type: String) -> Block? {
        guard let metadataContainerBlock = self.metadataBlock else {
            print("Failed to locate metadata block. Create one in the future.")
            return nil
        }
        
        guard let metaBlock = M4AFile.getMetadataBlock(metadataContainer:
            metadataContainerBlock, name: type) else {
                // Part of normal operating conditions
                //print("Failed to get metadata child block by type.")
            return nil
        }
        
        guard metaBlock.children.count == 1 else {
                print("Metadata entry lacked a data section.")
                return nil
        }
        
        return metaBlock.children[0]
    }
    
    /// Finds a block of the specified path
    ///
    /// - parameters:
    ///   - pathComponents: Block path components.
    ///     Given in the format `["foo", "bar", "oof"]` where `foo` is the
    ///     highest level and `oof` is the deepest level.
    ///
    /// - returns: The requested block if found
    internal func findBlock(_ pathComponents: [String]) -> Block? {
        assert(!pathComponents.isEmpty)
        
        var blocks = self.blocks
        for component in pathComponents {
            if let block = M4AFile.getBlockOneLevel(blocks: blocks,
                                                    type: component) {
                if component == pathComponents.last! {
                    return block
                } else {
                    blocks = block.children
                }
            } else {
                return nil
            }
        }
        return nil
    }
    
    /// Gets a block from the children of another block
    ///
    /// - parameters:
    ///   - blocks: The block children
    ///   - type: The block type to search for
    ///
    /// - returns: The requested block if it exists
    private static func getBlockOneLevel(blocks: [Block], type: String)
        -> Block? {
        for block in blocks {
            if block.type == type {
                return block
            }
        }
        return nil
    }
    
    /// Checks if a block type is valid
    ///
    /// - parameters:
    ///   - type: The block type
    ///
    /// - returns: The validity of the block type
    private func typeIsValid(_ type: String) -> Bool {
        return M4AFile.validTypes.contains(type)
    }
    
}
