import Foundation

public typealias DispatchIdentifier = String

/// The dispatcher service is used to forward an action to the stores that responds to it.
public final class ActionDispatch {
  /// The threading strategy that should be used for a given action.
  public enum Mode {
    /// The action is dispatched asynchronously on the main thread.
    case mainThread
    /// The action is dispatched synchronously on the main thread.
    case sync
    /// The action is dispatched on a serial background queue.
    case serial
    /// The action is being dispatched on a concurrent queue.
    case async
  }
  /// The global instance.
  public static let `default` = ActionDispatch()
  /// All the registered stores.
  private var stores: [StoreType] = []
  /// The background queue used for the .async mode.
  private let queue = OperationQueue()
  /// The serial queue used for the .serial mode.
  private let serialQueue = OperationQueue()
  /// The collection of middleware registered in the dispatcher.
  private var middleware: [MiddlewareType] = []

  /// Store getter function.
  /// - parameter identifier: The identifier of the registered store.
  /// - returns: The store with the given identifier (or *nil* if no store matches  the identifier).
  public func store(with identifier: String) -> StoreType? {
    return stores.filter { $0.identifier == identifier }.first
  }

  /// Register a store in this *ActionDispatch* instance.
  /// - parameter store: The store that will be registered in this dispatcher.
  /// - note: If a store with the same identifier is already registered in this dispatcher,
  /// this function is a no-op.
  public func register(store: StoreType) {
    precondition(Thread.isMainThread)
    guard stores.filter({ $0.identifier == store.identifier }).first == nil else { return }
    stores.append(store)
  }

  /// Unregister the store with the given identifier from this dispatcher.
  /// - parameter identifier: The identifier of the store.
  public func unregister(identifier: String) {
    precondition(Thread.isMainThread)
    stores = stores.filter { $0.identifier == identifier }
  }

  public func register(middleware: MiddlewareType) {
    precondition(Thread.isMainThread)
    self.middleware.append(middleware)
  }

  /// Dispatch an action and redirects it to the correct store.
  /// - parameter storeIdentifier: Optional, to target a specific store.
  /// - parameter action: The action that will be executed.
  /// - parameter mode: The threading strategy (default is *async*).
  /// - parameter completionBlock: Optional, completion block.
  public func dispatch(
    storeIdentifier: String? = nil,
    action: ActionType,
    mode: ActionDispatch.Mode = .async,
    then completionBlock: (() -> (Void))? = nil
  ) -> Void {
    var stores = self.stores
    if let storeIdentifier = storeIdentifier {
      stores = stores.filter { $0.identifier == storeIdentifier }
    }
    for store in stores where store.responds(to: action) {
      run(action: action, mode: mode, store: store, then: completionBlock)
    }
  }

  private func run(
    action: ActionType,
    mode: ActionDispatch.Mode = .serial,
    store: StoreType,
    then completionBlock: (() -> (Void))? = nil
  ) -> Void {
    // Create a transaction id for this action dispatch.
    // This is useful for the middleware to track down which action got completed.
    let transactionId = makePushID()
    // Get the operation.
    let operation = store.operation(action: action) {
      for mw in self.middleware {
        mw.didDispatch(transaction: transactionId, action: action, in: store)
      }
      // Dispatch chaining.
      if let completionBlock = completionBlock {
        DispatchQueue.main.async(execute: completionBlock)
      }
    }
    // If the store return a 'nil' operation
    guard let op = operation else { return }
    for mw in self.middleware {
      mw.willDispatch(transaction: transactionId, action: action, in: store)
    }
    // Dispatch the operation on the queue.
    switch mode {
    /// The action is dispatched synchronously on the main thread.
    case .async:
      self.queue.addOperation(op)
    /// The action is dispatched on a serial background queue.
    case .serial:
      self.serialQueue.addOperation(op)
    /// The action is dispatched synchronously on the main thread.
    case .sync:
      op.start()
      op.waitUntilFinished()
    /// The action is dispatched asynchronously on the main thread.
    case .mainThread:
      DispatchQueue.main.async {
        op.start()
        op.waitUntilFinished()
      }
    }
  }
}

/// Dispatch an action on the default *ActionDispatcher*  and redirects it to the correct store.
/// - parameter storeIdentifier: Optional, to target a specific store.
/// - parameter action: The action that will be executed.
/// - parameter mode: The threading strategy (default is *async*).
/// - parameter completionBlock: Optional, completion block.
public func dispatch(
  storeIdentifier: String? = nil,
  action: ActionType,
  mode: ActionDispatch.Mode = .async,
  then completionBlock: (() -> (Void))? = nil
) -> Void {
  ActionDispatch.default.dispatch(
    storeIdentifier: storeIdentifier,
    action: action,
    mode: mode,
    then: completionBlock)
}
