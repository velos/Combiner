//
//  View.swift
//  Pulled from in-progress:
//  https://github.com/ReactorKit/ReactorKit/blob/6e6216cb2d03b7bf4077c3bf47c5c55839451a48/Sources/ReactorKit-Combine/Stub.swift
//
//  Created by Zac White on 6/28/20.
//

import Combine

public protocol View: class, AssociatedObjectStore {
  associatedtype Combiner

  /// Cancellables. It is cancelled each time the `combiner` is assigned.
  var cancellables: Set<AnyCancellable> { get set }

  /// A view's combiner. `bind(combiner:)` gets called when the new value is assigned to this property.
  var combiner: Combiner? { get set }

  /// Creates bindings. This method is called each time the `combiner` is assigned.
  ///
  /// Here is a typical implementation example:
  ///
  /// ```
  /// func bind(combiner: MyCombiner) {
  ///    combiner.state.map { $0.test }
  ///        .removeDuplicates()
  ///        .assign(to: \.text, on: label)
  ///        .store(in: &cancellables)
  ///
  ///    button.publisher(for: .touchUpInside)
  ///        .map { _ in .buttonPressed }
  ///        .subscribe(combiner.action)
  ///        .store(in: &cancellables)
  ///}
  /// ```
  ///
  /// - warning: It's not recommended to call this method directly.
  func bind(combiner: Combiner)
}

// MARK: - Associated Object Keys
var combinerKey = "combiner"
var isCombinerBindedKey = "isCombinerBinded"


// MARK: - Default Implementations
extension View {
  public var combiner: Combiner? {
    get { return self.associatedObject(forKey: &combinerKey) }
    set {
      self.setAssociatedObject(newValue, forKey: &combinerKey)
      self.cancellables = .init()
      if let combiner = newValue {
        self.bind(combiner: combiner)
      }
    }
  }
}
