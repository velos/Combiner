//
//  Stub.swift
//  Pulled from in-progress:
//  https://github.com/ReactorKit/ReactorKit/blob/6e6216cb2d03b7bf4077c3bf47c5c55839451a48/Sources/ReactorKit-Combine/Stub.swift
//
//  Created by Zac White on 4/15/20.
//

import Combine

public class Stub<CombinerType: Combiner> {
    private unowned var combiner: CombinerType

    public let state: CurrentValueSubject<CombinerType.State, Never>
    public let action: PassthroughSubject<CombinerType.Action, Never>
    public private(set) var actions: [CombinerType.Action] = []

    public init(combiner: CombinerType, cancellables: inout Set<AnyCancellable>) {
        self.combiner = combiner
        self.state = .init(combiner.initialState)
        self.state
            .sink { [weak combiner] state in
                combiner?.currentState = state
        }
        .store(in: &cancellables)

        self.action = .init()
        self.action.eraseToAnyPublisher()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] action in
                    self?.actions.append(action)
                }
        )
            .store(in: &cancellables)
    }
}
