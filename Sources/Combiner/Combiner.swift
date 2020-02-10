import Foundation
import Combine
import SwiftUI

extension View {
    public func combinerEnvironment<V, T: Combiner>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, combiner: T, action: @escaping (V) -> T.Action) -> some View {
        return self.transformEnvironment(keyPath, transform: { value in
            combiner.action.send(action(value))
        })
    }

    public func subscribeCombiner<T: Combiner>(_ combiner: T) -> some View {
        return self.onReceive(combiner.state, perform: { _ in })
    }
}

@dynamicMemberLookup
public protocol Combiner: AssociatedObjectStore, ObservableObject, Identifiable {
    associatedtype State
    associatedtype Action
    associatedtype Mutation = Action

    var initialState: State { get }
    var currentState: State { get }

    var objectWillChange: ObservableObjectPublisher { get }

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

    subscript<U>(dynamicMember keyPath: KeyPath<State, U>) -> U { get }
}

extension Combiner {

    public func binding<U>(action: @escaping (U) -> Action, getter keyPath: KeyPath<State, U>) -> Binding<U> {
        return Binding(
            get: { self.currentState[keyPath: keyPath] },
            set: { self.action.send(action($0)) }
        )
    }

    public func binding<U>(action: @escaping (U) -> Action, getter closure: @escaping (State) -> U) -> Binding<U> {
        return Binding(
            get: { closure(self.currentState) },
            set: { self.action.send(action($0)) }
        )
    }

    public func binding<U>(getter keyPath: KeyPath<State, U>) -> Binding<U> {
        return Binding(
            get: { self.currentState[keyPath: keyPath] },
            set: { _ in }
        )
    }

    public func binding<U>(getter closure: @escaping (State) -> U) -> Binding<U> {
        return Binding(
            get: { closure(self.currentState) },
            set: { _ in }
        )
    }

    public subscript<U>(dynamicMember keyPath: KeyPath<State, U>) -> U {
        return currentState[keyPath: keyPath]
    }

    public func action(_ action: Action) -> () -> Void {
        // create a state stream if it doesn't exist already.
        _ = self._state

        return {
            self.action.send(action)
        }
    }

    public func environment<V>(_ environment: EnvironmentObject<V>, action: @escaping (V.ObjectWillChangePublisher.Output) -> Action) -> AnyCancellable {
        return environment.wrappedValue.objectWillChange.sink { (value: V.ObjectWillChangePublisher.Output) in
            self.action.send(action(value))
        }
    }
}

private struct CombinerEnvironmentObservingView<V: View, C: Combiner, E: ObservableObject>: View {
    let originalView: V
    let combiner: C
    let environment: EnvironmentObject<E>
    let action: (E.ObjectWillChangePublisher.Output) -> C.Action

    @State private var cancellable: Cancellable?

    var body: some View {
        originalView.onAppear {
            self.cancellable = self.combiner.environment(self.environment, action: self.action)
        }
        .onDisappear {
            self.cancellable = nil
        }
    }
}

extension View {
    public func combinerEnvironmentObserve<V, T: Combiner>(_ environment: EnvironmentObject<V>, combiner: T, action: @escaping (V.ObjectWillChangePublisher.Output) -> T.Action) -> some View {
        return CombinerEnvironmentObservingView(originalView: self, combiner: combiner, environment: environment, action: action)
    }
}

extension Combiner {
    public var objectWillChange: ObservableObjectPublisher {
        return _willChange
    }
}

@objc
class CancelBox: NSObject {

    private let cancellable: AnyCancellable

    init(cancellable: AnyCancellable) {
        self.cancellable = cancellable
    }

    deinit {
        cancellable.cancel()
    }
}

private var actionKey = "action"
private var willChangeKey = "willChange"
private var currentStateKey = "currentState"
private var stateKey = "state"
private var cancellableKey = "cancellable"
private var identifier = "identifier"

extension Combiner {

    private var _willChange: ObservableObjectPublisher {
        return self.associatedObject(forKey: &willChangeKey, default: .init())
    }

    private var _action: PassthroughSubject<Action, Never> {
        return self.associatedObject(forKey: &actionKey, default: .init())
    }

    public var action: PassthroughSubject<Action, Never> {
        // Creates a state stream automatically
        _ = self._state

        return _action
    }

    public var id: String {
        return self.associatedObject(forKey: &identifier, default: UUID().uuidString)
    }

    public internal(set) var currentState: State {
        get { return self.associatedObject(forKey: &currentStateKey, default: self.initialState) }
        set {
            self._willChange.send()
            self.setAssociatedObject(newValue, forKey: &currentStateKey)
        }
    }

    private var _cancellables: Set<CancelBox> {
        get { return self.associatedObject(forKey: &cancellableKey, default: Set<CancelBox>()) }
        set { self.setAssociatedObject(newValue, forKey: &cancellableKey) }
    }

    private var _state: AnyPublisher<State, Never> {
        return self.associatedObject(forKey: &stateKey, default: self.createStateStream())
    }
    public var state: AnyPublisher<State, Never> {
        // It seems that Swift has a bug in associated object when subclassing a generic class. This is
        // a temporary solution to bypass the bug. See #30 for details.
        return self._state
    }

    public func createStateStream() -> AnyPublisher<State, Never> {

        let action = self._action.eraseToAnyPublisher()
        let transformedAction = self.transform(action: action)

        let mutation = transformedAction
            .flatMap { [weak self] action -> AnyPublisher<Mutation, Never> in
                guard let self = self else { return Empty().eraseToAnyPublisher() }
                return self.mutate(action: action)
                    .receive(on: DispatchQueue.main)
                    .eraseToAnyPublisher()
            }.eraseToAnyPublisher()

        let transformedMutation = self.transform(mutation: mutation)

        let state = transformedMutation
            .scan(initialState, { [weak self] (state, mutation) -> State in
                guard let self = self else { return state }
                return self.reduce(state: state, mutation: mutation)
            })
            .prepend(initialState)
            .eraseToAnyPublisher()

        let transformed = self.transform(state: state)
            .handleEvents(receiveOutput: { [weak self] newState in
                self?.currentState = newState
            })
            .share()
            .eraseToAnyPublisher()

        let cancellable = transformed
            .sink(receiveValue: { _ in })

        _cancellables.insert(CancelBox(cancellable: cancellable))

        return transformed
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
