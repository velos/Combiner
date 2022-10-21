import Foundation
import Combine

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
    public subscript<U>(dynamicMember keyPath: KeyPath<State, U>) -> U {
        return currentState[keyPath: keyPath]
    }
}

private var actionKey = "action"
private var willChangeKey = "willChange"
private var currentStateKey = "currentState"
private var stateKey = "state"
private var cancellableKey = "cancellable"
private var hasInitializedKey = "hasInitialized"
private var identifier = "identifier"
private var isStubEnabledKey = "isStubEnabled"
private var stubKey = "stub"

extension Combiner where State: Equatable {
    public var state: AnyPublisher<State, Never> {
        // It seems that Swift has a bug in associated object when subclassing a generic class. This is
        // a temporary solution to bypass the bug. See #30 for details.
        return self._state.removeDuplicates().eraseToAnyPublisher()
    }
}

// swiftlint:disable identifier_name
extension Combiner {

    var _willChange: ObservableObjectPublisher {
        return self.associatedObject(forKey: &willChangeKey, default: .init())
    }

    var _action: PassthroughSubject<Action, Never> {
        return self.associatedObject(forKey: &actionKey, default: .init())
    }

    public var action: PassthroughSubject<Action, Never> {
        // Creates a state stream automatically
        _ = self._state

        return self._action
    }

    private var hasInitialized: Bool {
        get { self.associatedObject(forKey: &hasInitializedKey, default: false) }
        set { self.setAssociatedObject(newValue, forKey: &hasInitializedKey) }
    }

    public var id: String {
        return self.associatedObject(forKey: &identifier, default: UUID().uuidString)
    }

    public internal(set) var currentState: State {
        get { return self.associatedObject(forKey: &currentStateKey, default: self.initialState) }
        set {
            let update = {
                self._willChange.send()
                self.setAssociatedObject(newValue, forKey: &currentStateKey)
                self.hasInitialized = true
            }

            DispatchQueue.main.async(execute: update)
        }
    }

    var _cancellables: Set<AnyCancellable> {
        get { return self.associatedObject(forKey: &cancellableKey, default: Set<AnyCancellable>()) }
        set { self.setAssociatedObject(newValue, forKey: &cancellableKey) }
    }

    var _state: AnyPublisher<State, Never> {
        if self.isStubEnabled {
            return self.stub.state.eraseToAnyPublisher()
        } else {
            return self.associatedObject(forKey: &stateKey, default: self.createStateStream())
        }
    }

    public var state: AnyPublisher<State, Never> {
        return self._state
    }

    private func createStateStream() -> AnyPublisher<State, Never> {

        let action = self._action.eraseToAnyPublisher()
        let transformedAction = self.transform(action: action)

        let mutation = transformedAction
            .flatMap { [weak self] action -> AnyPublisher<Mutation, Never> in
                guard let self = self else { return Empty().eraseToAnyPublisher() }
                return self.mutate(action: action)
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
            .share()

        transformed
            .sink { [weak self] newState in
                self?.currentState = newState
            }
            .store(in: &_cancellables)

        return transformed
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
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

extension Combiner {
    public var isStubEnabled: Bool {
        set { self.setAssociatedObject(newValue, forKey: &isStubEnabledKey) }
        get { return self.associatedObject(forKey: &isStubEnabledKey, default: false) }
    }

    public var stub: Stub<Self> {
        return self.associatedObject(
            forKey: &stubKey,
            default: Stub(combiner: self, cancellables: &_cancellables)
        )
    }

    public func stubbed(with state: Self.State) -> Self {
        self.isStubEnabled = true
        self.stub.state.send(state)
        return self
    }

    public func stubbed() -> Self {
        self.isStubEnabled = true
        return self
    }
}

extension Combiner where Action == Mutation {
    public func mutate(action: Action) -> AnyPublisher<Mutation, Never> {
        return Just(action).eraseToAnyPublisher()
    }
}

extension Combiner {
    public var objectWillChange: ObservableObjectPublisher {
        return _willChange
    }
}

// swiftlint:enable identifier_name
