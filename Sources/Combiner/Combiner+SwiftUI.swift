//
//  Combiner+SwiftUI.swift
//  
//
//  Created by Zac White on 3/31/20.
//

import Foundation
import Combine
import SwiftUI

extension SwiftUI.View {
    public func combinerEnvironment<V, T: Combiner>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, combiner: T, action: @escaping (V) -> T.Action) -> some SwiftUI.View {
        return self.transformEnvironment(keyPath, transform: { [weak combiner] value in
            combiner?.action.send(action(value))
        })
    }

    public func subscribeCombiner<T: Combiner>(_ combiner: T) -> some SwiftUI.View {
        return self.onReceive(combiner.state, perform: { _ in })
    }
}

extension Combiner {

    public func binding<U>(action: @escaping (U) -> Self.Action, getter closure: @escaping (Self.State) -> U) -> Binding<U> {
        return Binding(
            get: { closure(self.currentState) },
            set: { [weak self] (value: U) in
                self?.action.send(action(value))
            }
        )
    }

    public func binding<U>(getter closure: @escaping (Self.State) -> U) -> Binding<U> {
        return Binding(
            get: { closure(self.currentState) },
            set: { _ in }
        )
    }

    public func action(_ action: Self.Action) -> () -> Void {
        // create a state stream if it doesn't exist already.
        createStateStreamIfNecessary()

        return { [weak self] in
            self?.action.send(action)
        }
    }

    public func environment<V>(_ environment: EnvironmentObject<V>, action: @escaping (V.ObjectWillChangePublisher.Output) -> Action) -> AnyCancellable {
        return environment.wrappedValue.objectWillChange.sink { [weak self] (value: V.ObjectWillChangePublisher.Output) in
            self?.action.send(action(value))
        }
    }
}

private struct CombinerEnvironmentObservingView<V: SwiftUI.View, C: Combiner, E: ObservableObject>: SwiftUI.View {
    let originalView: V
    let combiner: C
    let environment: EnvironmentObject<E>
    let action: (E.ObjectWillChangePublisher.Output) -> C.Action

    @State private var cancellable: Cancellable?

    var body: some SwiftUI.View {
        originalView.onAppear {
            self.cancellable = self.combiner.environment(self.environment, action: self.action)
        }
        .onDisappear {
            DispatchQueue.main.async {
                self.cancellable = nil
            }
        }
    }
}

extension SwiftUI.View {
    public func combinerEnvironmentObserve<V, T: Combiner>(_ environment: EnvironmentObject<V>, combiner: T, action: @escaping (V.ObjectWillChangePublisher.Output) -> T.Action) -> some SwiftUI.View {
        return CombinerEnvironmentObservingView(originalView: self, combiner: combiner, environment: environment, action: action)
    }
}
