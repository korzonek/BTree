//
//  Map.swift
//  TreeCollections
//
//  Created by Károly Lőrentey on 2015-12-17.
//  Copyright © 2015 Károly Lőrentey.
//

import Foundation

/// An ordered mapping from comparable keys to arbitrary values. 
/// Works like `Dictionary`, but provides a well-defined ordering for its elements.
///
/// `Map` is a struct with copy-on-write value semantics, like Swift's standard collection types.
/// It uses an in-memory b-tree for element storage, whose individual nodes may be shared with other maps.
/// Modifying an element of a map whose storage is (partially or completely) shared requires copying of 
/// only O(log(`count`)) elements. (Thus, mutation of shared maps may be relatively cheaper than dictionaries, 
/// which need to clone all elements.)
///
/// Lookup, insertion and removal of individual key-value pairs in a map have logarithmic complexity.
/// This is in contrast to `Dictionary`'s best-case O(1) (worst-case O(n)) implementations for the same operations.
/// To make up for being typically slower, `Map` always keeps its elements in a well-defined order.
///
/// While independently looking up individual elements takes O(log(n)) time, batch operations on lots of elements
/// often complete faster than you might expect.
/// For example, iterating over a `Map` using the generator API requires O(n) time, just like a dictionary.
///
/// Due to its tree-based structure, `Map` is able to provide efficient implementations for several operations 
/// that would be slower with dictionaries.
///
public struct Map<Key: Comparable, Value> {
    // Typealiases
    internal typealias Tree = BTree<Key, Value>

    /// The root node.
    internal private(set) var tree: Tree

    /// Initialize an empty map.
    public init() {
        self.tree = Tree()
    }
}

//MARK: CollectionType

extension Map: CollectionType {
    public typealias Index = BTreeIndex<Key, Value>
    public typealias Generator = BTreeGenerator<Key, Value>
    public typealias Element = (Key, Value)

    /// The index of the first element when non-empty. Otherwise the same as `endIndex`.
    public var startIndex: Index {
        return tree.startIndex
    }

    /// The "past-the-end" element index; the successor of the last valid subscript argument.
    public var endIndex: Index {
        return tree.endIndex
    }

    /// The number of (key, value) pairs in this map.
    ///
    /// - Complexity: O(1)
    public var count: Int {
        return tree.count
    }

    /// True iff this collection has no elements.
    public var isEmpty: Bool {
        return count == 0
    }

    /// Returns the (key, value) pair at the given index.
    ///
    /// - Requires: `index` originated from an unmutated copy of this map.
    /// - Complexity: O(1)
    public subscript(index: Index) -> Element {
        return tree[index]
    }

    /// Return a generator over all (key, value) pairs in this map, in ascending key order.
    @warn_unused_result
    public func generate() -> Generator {
        return tree.generate()
    }
}

//MARK: Algorithms

extension Map {
    /// Call `body` on each element in `self` in ascending key order.
    ///
    /// - Complexity: O(`count`)
    public func forEach(@noescape body: (Element) throws -> ()) rethrows {
        try tree.forEach(body)
    }

    /// Return an `Array` containing the results of mapping `transform` over all elements in `self`.
    /// The elements are transformed in ascending key order.
    ///
    /// - Complexity: O(`count`)
    @warn_unused_result
    public func map<T>(@noescape transform: (Element) throws -> T) rethrows -> [T] {
        var result: [T] = []
        result.reserveCapacity(self.count)
        try self.forEach {
            result.append(try transform($0))
        }
        return result
    }

    /// Return an `Array` containing the concatenated results of mapping `transform` over `self`.
    ///
    /// - Complexity: O(`count`)
    @warn_unused_result
    public func flatMap<S: SequenceType>(transform: (Element) throws -> S) rethrows -> [S.Generator.Element] {
        var result: [S.Generator.Element] = []
        try self.forEach { element in
            result.appendContentsOf(try transform(element))
        }
        return result
    }

    /// Return an `Array` containing the non-`nil` results of mapping `transform` over `self`.
    ///
    /// - Complexity: O(`count`)
    @warn_unused_result
    public func flatMap<T>(@noescape transform: (Element) throws -> T?) rethrows -> [T] {
        var result: [T] = []
        try self.forEach { element in
            if let t = try transform(element) {
                result.append(t)
            }
        }
        return result
    }

    /// Calculate the left fold of this map over `combine`:
    /// return the result of repeatedly calling `combine` with an accumulated value initialized to `initial`
    /// and each element of `self`, in turn. 
    ///
    /// I.e., return `combine(combine(...combine(combine(initial, self[0]), self[1]),...self[count-2]), self[count-1])`.
    ///
    /// - Complexity: O(`count`)
    @warn_unused_result
    public func reduce<T>(initial: T, @noescape combine: (T, Element) throws -> T) rethrows -> T {
        var result = initial
        try self.forEach {
            result = try combine(result, $0)
        }
        return result
    }
}

//MARK: Dictionary-like methods

extension Map {

    /// A collection containing just the keys in this map, in ascending order.
    public var keys: LazyMapCollection<Map<Key, Value>, Key> {
        return self.lazy.map { $0.0 }
    }

    /// A collection containing just the values in this map, in order of ascending keys.
    public var values: LazyMapCollection<Map<Key, Value>, Value> {
        return self.lazy.map { $0.1 }
    }

    /// Provides access to the value for a given key. Nonexistent values are represented as `nil`.
    /// 
    /// - Complexity: O(log(`count`))
    public subscript(key: Key) -> Value? {
        get {
            return tree.payloadOf(key)
        }
        set(value) {
            if let value = value {
                updateValue(value, forKey: key)
            }
            else {
                removeValueForKey(key)
            }
        }
    }

    /// Returns the index for the given key, or `nil` if the key is not present in this map.
    ///
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func indexForKey(key: Key) -> Index? {
        return tree.indexOf(key)
    }

    /// Update the value stored in the map for the given key, or, if they key does not exist, add a new key-value pair to the map.
    /// Returns the value that was replaced, or `nil` if a new key-value pair was added.
    ///
    /// This method invalidates all existing indexes into `self`.
    ///
    /// - Complexity: O(log(`count`))
    public mutating func updateValue(value: Value, forKey key: Key) -> Value? {
        return tree.insertOrReplace((key, value))
    }

    /// Remove the key-value pair at `index` from this map.
    ///
    /// This method invalidates all existing indexes into `self`.
    ///
    /// - Complexity: O(log(`count`))
    public mutating func removeAtIndex(index: Index) -> (Key, Value) {
        let key = self[index].0
        return (key, self.removeValueForKey(key)!)
    }

    /// Remove a given key and the associated value from this map.
    /// Returns the value that was removed, or `nil` if the key was not present in the map.
    ///
    /// This method invalidates all existing indexes into `self`.
    ///
    /// - Complexity: O(log(`count`))
    public mutating func removeValueForKey(key: Key) -> Value? {
        return tree.remove(key)
    }

    /// Remove all elements from this map.
    ///
    /// This method invalidates all existing indexes into `self`.
    ///
    /// - Complexity: O(`count`)
    public mutating func removeAll() {
        tree = Tree()
    }
}

extension Map {
    /// Initialize a new map from an unsorted sequence of elements.
    ///
    /// - Complexity: O(*n* * log(*n*)) where *n* is the number of items in `elements`.
    public init<S: SequenceType where S.Generator.Element == Element>(elements: S) {
        self.tree = Tree(elements: elements)
    }

    /// Initialize a new map from a sorted sequence of elements.
    ///
    /// - Complexity: O(*n*) where *n* is the number of items in `elements`.
    public init<S: SequenceType where S.Generator.Element == Element>(sortedElements elements: S) {
        self.tree = Tree(sortedElements: elements)
    }
}

extension Map: DictionaryLiteralConvertible {
    /// Initialize a new map from the given elements.
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.tree = Tree(elements: elements)
    }
}

extension Map: CustomStringConvertible {
    /// A textual representation of this map.
    public var description: String {
        let contents = self.map { (key, value) -> String in
            let ks = String(reflecting: key)
            let vs = String(reflecting: value)
            return "\(ks): \(vs)"
        }
        return "[" + contents.joinWithSeparator(", ") + "]"
    }
}

extension Map: CustomDebugStringConvertible {
    /// A textual representation of this map, suitable for debugging.
    public var debugDescription: String {
        let contents = self.map { (key, value) -> String in
            let ks = String(reflecting: key)
            let vs = String(reflecting: value)
            return "\(ks): \(vs)"
        }
        return "[" + contents.joinWithSeparator(", ") + "]"
    }
}

@warn_unused_result
public func ==<Key: Comparable, Value: Equatable>(a: Map<Key, Value>, b: Map<Key, Value>) -> Bool {
    guard a.count == b.count else { return false }
    return a.elementsEqual(b, isEquivalent: { ae, be in ae.0 == be.0 && ae.1 == be.1 })
}

@warn_unused_result
public func !=<Key: Comparable, Value: Equatable>(a: Map<Key, Value>, b: Map<Key, Value>) -> Bool {
    return !(a == b)
}
