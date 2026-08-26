//
//  FileObject.swift
//  FileProvider
//
//  Created by kintan
//

import Foundation
import KSPlayer

extension FileObject {
    func mapPredicate() -> [String: Any] {
        let mapDict: [URLResourceKey: String] = [.fileURLKey: "url", .nameKey: "name", .pathKey: "path",
                                                 .fileSizeKey: "fileSize", .creationDateKey: "creationDate",
                                                 .contentModificationDateKey: "modifiedDate", .isHiddenKey: "isHidden",
                                                 .isWritableKey: "isWritable", .serverDateKey: "serverDate",
                                                 .entryTagKey: "entryTag", .mimeTypeKey: "mimeType"]
        let typeDict: [URLFileResourceType: String] = [.directory: "directory", .regular: "regular",
                                                       .symbolicLink: "symbolicLink", .unknown: "unknown"]
        var result = [String: Any]()
        for (key, value) in allValues {
            if let convertkey = mapDict[key] {
                result[convertkey] = value
            }
        }
        result["eTag"] = result["entryTag"]
        result["filesize"] = result["fileSize"]
        result["isReadOnly"] = isReadOnly
        result["isDirectory"] = isDirectory
        result["isRegularFile"] = isRegularFile
        result["isSymLink"] = isSymLink
        result["type"] = typeDict[type] ?? "unknown"
        return result
    }

    /// Converts macOS spotlight query for searching files to a query that can be used for `searchFiles()` method
    public static func convertPredicate(fromSpotlight query: NSPredicate) -> NSPredicate {
        let mapDict: [String: URLResourceKey] = [NSMetadataItemURLKey: .fileURLKey, NSMetadataItemFSNameKey: .nameKey,
                                                 NSMetadataItemPathKey: .pathKey, NSMetadataItemFSSizeKey: .fileSizeKey,
                                                 NSMetadataItemFSCreationDateKey: .creationDateKey, NSMetadataItemFSContentChangeDateKey: .contentModificationDateKey,
                                                 "kMDItemFSInvisible": .isHiddenKey, "kMDItemFSIsWriteable": .isWritableKey,
                                                 "kMDItemKind": .mimeTypeKey]

        if let cQuery = query as? NSCompoundPredicate {
            let newSub = cQuery.subpredicates.map { convertPredicate(fromSpotlight: $0 as! NSPredicate) }
            switch cQuery.compoundPredicateType {
            case .and: return NSCompoundPredicate(andPredicateWithSubpredicates: newSub)
            case .not: return NSCompoundPredicate(notPredicateWithSubpredicate: newSub[0])
            case .or: return NSCompoundPredicate(orPredicateWithSubpredicates: newSub)
            @unknown default: fatalError()
            }
        } else if let cQuery = query as? NSComparisonPredicate {
            var newLeft = cQuery.leftExpression
            var newRight = cQuery.rightExpression
            if newLeft.expressionType == .keyPath, let newKey = mapDict[newLeft.keyPath] {
                newLeft = NSExpression(forKeyPath: newKey.rawValue)
            }
            if newRight.expressionType == .keyPath, let newKey = mapDict[newRight.keyPath] {
                newRight = NSExpression(forKeyPath: newKey.rawValue)
            }
            return NSComparisonPredicate(leftExpression: newLeft, rightExpression: newRight, modifier: cQuery.comparisonPredicateModifier, type: cQuery.predicateOperatorType, options: cQuery.options)
        } else {
            return query
        }
    }
}

public extension FileObject {
    /// Determines sort kind by which item of File object
    enum SortType: Int, Sendable {
        case none
        /// Sorting by default Finder (case-insensitive) behavior
        case name
        /// Sorting by case-sensitive form of file name
        case nameCaseSensitive
        /// Sorting by case-in sensitive form of file name
        case nameCaseInsensitive
        /// Sorting by file type
        case `extension`
        /// Sorting by file modified date
        case modifiedDate
        /// Sorting by file creation date
        case creationDate
        /// Sorting by file modified date
        case fileSize
    }
}

public extension [FileObject] {
    mutating func sort(by type: FileObject.SortType, ascending: Bool = true, isDirectoriesFirst: Bool = true) {
        self = sorted(by: type, ascending: ascending, isDirectoriesFirst: isDirectoriesFirst)
    }

    func sorted(by type: FileObject.SortType, ascending: Bool = true, isDirectoriesFirst: Bool = true) -> [FileObject] {
        guard type != .none else {
            return self
        }
        return sorted {
            if isDirectoriesFirst {
                if $0.isDirectory, !($1.isDirectory) {
                    return true
                }
                if !($0.isDirectory), $1.isDirectory {
                    return false
                }
            }
            switch type {
            case .name:
                return ($0.name).localizedStandardCompare($1.name) == (ascending ? .orderedAscending : .orderedDescending)
            case .nameCaseSensitive:
                return ($0.name).localizedCompare($1.name) == (ascending ? .orderedAscending : .orderedDescending)
            case .nameCaseInsensitive:
                return ($0.name).localizedCaseInsensitiveCompare($1.name) == (ascending ? .orderedAscending : .orderedDescending)
            case .extension:
                let kind1 = $0.isDirectory ? "folder" : $0.path.pathExtension
                let kind2 = $1.isDirectory ? "folder" : $1.path.pathExtension
                return kind1.localizedCaseInsensitiveCompare(kind2) == (ascending ? .orderedAscending : .orderedDescending)
            case .modifiedDate:
                let fileMod1 = $0.modifiedDate ?? Date.distantPast
                let fileMod2 = $1.modifiedDate ?? Date.distantPast
                return ascending ? fileMod1 < fileMod2 : fileMod1 > fileMod2
            case .creationDate:
                let fileCreation1 = $0.creationDate ?? Date.distantPast
                let fileCreation2 = $1.creationDate ?? Date.distantPast
                return ascending ? fileCreation1 < fileCreation2 : fileCreation1 > fileCreation2
            case .fileSize:
                return ascending ? $0.fileSize < $1.fileSize : $0.fileSize > $1.fileSize
            case .none:
                return false
            }
        }
    }
}

extension String {
    var pathExtension: String {
        (self as NSString).pathExtension
    }
}
