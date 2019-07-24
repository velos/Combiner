import Foundation
import Combine
import SwiftUI

@dynamicMemberLookup
public protocol Combiner: AssociatedObjectStore, BindableObject {
    associatedtype State
    associatedtype Action
    associatedtype Mutation = Action

    var initialState: State { get }
    var currentState: State { get }

    /// Commits mutation from the action. This is the best place to perform side-effects such as
    /// async tasks.
    func mutate(action: Action) -> AnyPublisher<Mutation, Never>

    /// Generates a new state with the previous state and the action. It should be purely functional
    /// so it should not perform any side-effects here. This method is called every time when the
    /// mutation is committed.
    func reduce(state: State, mutation: Mutation) -> State

    /// Transforms the mutation stream. Implement this method to transform or combine with other
    /// observables. This method is called once before the state stream is created.
    func transform(mutation: AnyPublisher<Mutation, Never>) -> AnyPublisher<Mutation, Never>

    /// Transforms the action. Use this function to combine with other observables. This method is
    /// called once before the state stream is created.
    func transform(action: AnyPublisher<Action, Never>) -> AnyPublisher<Action, Never>

    var action: PassthroughSubject<Action, Never> { get }
    var state: AnyPublisher<State, Never> { get }

    subscript<U>(dynamicMember keyPath: WritableKeyPath<State, U>) -> Binding<U> { get }
}

extension Combiner {
    public subscript<U>(dynamicMember keyPath: WritableKeyPath<State, U>) -> Binding<U> {
        return Binding(getValue: {
            return self.currentState[keyPath: keyPath]
        }, setValue: { value in
            self.updateState(value: value, keyPath: keyPath)
        })
    }
}

extension Combiner {
    public var willChange: AnyPublisher<State, Never> {
        return state
    }
}

private var actionKey = "action"
private var currentStateKey = "currentState"
private var stateKey = "state"
private var manualStateUpdateKey = "manualStateUpdate"
private var cancellableKey = "cancellable"

extension Combiner {
    private var _action: PassthroughSubject<Action, Never> {
        return self.associatedObject(forKey: &actionKey, default: .init())
    }

    public var action: PassthroughSubject<Action, Never> {
        // Creates a state stream automatically
        _ = self._state

        // It seems that Swift has a bug in associated object when subclassing a generic class. This is
        // a temporary solution to bypass the bug. See #30 for details.
        return self._action
    }

    public internal(set) var currentState: State {
        get { return self.associatedObject(forKey: &currentStateKey, default: self.initialState) }
        set { self.setAssociatedObject(newValue, forKey: &currentStateKey) }
    }

    private var _state: AnyPublisher<State, Never> {
        return self.associatedObject(forKey: &stateKey, default: self.createStateStream())
    }
    public var state: AnyPublisher<State, Never> {
        // It seems that Swift has a bug in associated object when subclassing a generic class. This is
        // a temporary solution to bypass the bug. See #30 for details.
        return self._state
    }

    fileprivate var manualStateUpdate: PassthroughSubject<State, Never> {
        return self.associatedObject(forKey: &manualStateUpdateKey, default: PassthroughSubject<State, Never>())
    }

    fileprivate func updateState<U>(value: U, keyPath: WritableKeyPath<State, U>) {
        currentState[keyPath: keyPath] = value
        manualStateUpdate.send(currentState)
    }

    fileprivate var cancellable: Cancellable? {
        get { return self.associatedObject(forKey: &cancellableKey, default: nil) }
        set { self.setAssociatedObject(newValue, forKey: &cancellableKey)}
    }

    public func createStateStream() -> AnyPublisher<State, Never> {
        let action = self._action.eraseToAnyPublisher()
        let transformedAction = self.transform(action: action)

        let mutation = transformedAction
            .flatMap { [weak self] action -> AnyPublisher<Mutation, Never> in
                guard let self = self else { return Empty().eraseToAnyPublisher() }
                return self.mutate(action: action)
            }.eraseToAnyPublisher()
        let transformedMutation = self.transform(mutation: mutation)

        let state = transformedMutation
            .scan(initialState, { [weak self] (state, mutation) -> State in
                guard let self = self else { return state }
                return self.reduce(state: state, mutation: mutation)
            })
            .prepend(initialState)
            .eraseToAnyPublisher()

        let transformedState = Publishers.Merge(
            self.transform(state: state),
            manualStateUpdate
        ).eraseToAnyPublisher()

        self.cancellable = transformedState
            .assign(to: \.currentState, on: self)

        return transformedState
    }

    public func transform(action: AnyPublisher<Action, Never>) -> AnyPublisher<Action, Never> {
        return action
    }

    public func mutate(action: Action) -> AnyPublisher<Mutation, Never> {
        return Empty().eraseToAnyPublisher()
    }

    public func transform(mutation: AnyPublisher<Mutation, Never>) -> AnyPublisher<Mutation, Never> {
        return mutation
    }

    public func reduce(state: State, mutation: Mutation) -> State {
        return state
    }

    public func transform(state: AnyPublisher<State, Never>) -> AnyPublisher<State, Never> {
        return state
    }
}

extension Combiner where Action == Mutation {
    public func mutate(action: Action) -> AnyPublisher<Mutation, Never> {
        return Just(action).eraseToAnyPublisher()
    }
}
