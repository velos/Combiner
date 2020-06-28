//
//  StoryboardView.swift
//  Pulled from in-progress:
//  https://github.com/ReactorKit/ReactorKit/blob/6e6216cb2d03b7bf4077c3bf47c5c55839451a48/Sources/ReactorKit-Combine/Stub.swift
//
//  Created by Zac White on 6/28/20.
//

import Combine

#if os(iOS) || os(tvOS)
import UIKit
private typealias OSViewController = UIViewController
#elseif os(OSX)
import AppKit
private typealias OSViewController = NSViewController
#endif

public protocol _ObjCStoryboardView {
  func performBinding()
}

public protocol StoryboardView: View, _ObjCStoryboardView {
}

extension StoryboardView {
  public var combiner: Combiner? {
    get { return self.associatedObject(forKey: &combinerKey) }
    set {
      self.setAssociatedObject(newValue, forKey: &combinerKey)
      self.isCombinerBinded = false
      self.cancellables = .init()
      self.performBinding()
    }
  }

  private var isCombinerBinded: Bool {
    get { return self.associatedObject(forKey: &isCombinerBindedKey, default: false) }
    set { self.setAssociatedObject(newValue, forKey: &isCombinerBindedKey) }
  }

  public func performBinding() {
    guard let combiner = self.combiner else { return }
    guard !self.isCombinerBinded else { return }
    guard !self.shouldDeferBinding(combiner: combiner) else { return }
    self.bind(combiner: combiner)
    self.isCombinerBinded = true
  }

  private func shouldDeferBinding(combiner: Combiner) -> Bool {
    #if !os(watchOS)
      return (self as? OSViewController)?.isViewLoaded == false
    #else
      return false
    #endif
  }
}

#if !os(watchOS)
extension OSViewController {
  @objc func _combinerkit_performBinding() {
    (self as? _ObjCStoryboardView)?.performBinding()
  }
}
#endif
