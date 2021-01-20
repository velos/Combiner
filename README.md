# Combiner

A 1:1 port of [ReactorKit](https://github.com/ReactorKit/ReactorKit) using Combine instead of RxSwift. Also includes some basic extensions for working with SwiftUI.

## Basic Architecture

Combiners are state machines which take in Actions and produce States which can be bound to UI elements in UIViewControllers or SwiftUI views.

This allows an implementation of unidirectional architecture, where inputs from the UI go into the Combiner to produce outputs of state changes.

<img src="https://user-images.githubusercontent.com/2525/105243110-70d62f00-5b23-11eb-831c-5c69526fe8be.png" width="600px" alt="Combiner data flow" />

## Usage

Using a Combiner first requires creating a subclass of `Combiner`. The subclass must create an associated type for `State` which is the view state represented by the Combiner. It also must create an `Action` associated type, usually declared as an enum, which defines all the inputs the Combiner will get from the view. Next, the internal `Mutation` is associated as well, again usually as an enum. The `Mutation` type defines the operations that can be made to the `State` and very often, but not necessarily, is 1:1 with properties of the `State`.

After these types are declared, the following functions are required to be implemented:

* `func mutate(action: Action) -> AnyPublisher<Mutation, Never>`
  * Implements taking an incoming action and producing a publisher which produces zero or more mutations that are applied serially to the outgoing view state.
* `func reduce(state: State, mutation: Mutation) -> State`
  * Takes the mutations that are being produced as a result of the outputs to the publisher from the mutate function and applies them to the current state to produce a new state.

Now the `state` property is available on the combiner to observe and bind to changes to the view.

## More Information

For more information, please check out the [ReactorKit](https://github.com/ReactorKit/ReactorKit) repo since almost all implementation details apply to this port.
