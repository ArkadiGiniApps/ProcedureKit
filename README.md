# Operations

[![Build status](https://badge.buildkite.com/4bc80b0824c6357ae071342271cb503b8994cf0cfa58645849.svg?branch=master)](https://buildkite.com/blindingskies/operations)

A Swift framework inspired by WWDC 2015 Advanced NSOperations session. See the session video here: https://developer.apple.com/videos/wwdc/2015/?id=226

## Status - 21st Sept, 2015

The Swift 1.2 compatible version of Operations is version 1.0. This is no longer under active development, however if you’re still stuck on Swift 1.2, and have a bug, please create ticket and I’ll do a point release.

Development from now on is using Swift 2.0, for all of Apple’s platforms as of version 2.1, which adds support for OS X and extension compatible frameworks. watchOS 2.0 and tvOS frameworks are built (if using the correct version of Xcode), however, the current version of Cocoapods (0.38.2) doesn’t yet support these platforms correctly. I’ll be looking into Carthage support in the coming week.

## Usage

`NSOperation` is a class which enables composition of discrete tasks or work for asynchronous execution on an operation queue. It is therefore an abstract class, and `Operation` is a similar abstract class. Therefore, typical usage in your own codebase would be to subclass `Operation` and override `execute`.

For example, an operation to save a `Contact` value in `YapDatabase` might be:

```swift
class SaveContactOperation: Operation {
    typealias CompletionBlockType = Contact -> Void

    let connection: YapDatabaseConnection
    let contact: Contact
    let completion: CompletionBlockType?

    init(connection: YapDatabaseConnection, contact: Contact, completion: CompletionBlockType? = .None) {
        self.connection = connection
        self.contact = contact
        self.completion = completion
        super.init()
        name = “Save Contact: \(contact.displayName)”
    }

    override func execute() {
        connection.asyncWrite(contact) { (returned: Contact) in
            self.completion?(returned)
            self.finish()
        }
    }
}
```

The power of the `Operations` framework however, comes with attaching conditions and observer to operations. For example, perhaps before the user is allowed to delete a `Contact`, we want them to confirm their intention. We can achieve this using the supplied `UserConfirmationCondition`.

```swift
func deleteContact(contact: Contact) {
    let delete = DeleteContactOperation(connection: readWriteConnection, contact: contact)
    let confirmation = UserConfirmationCondition(
        title: NSLocalizedString("Are you sure?", comment: "Are you sure?"),
        message: NSLocalizedString("The contact will be removed from all your devices.", comment: "The contact will be removed from all your devices."),
        action: NSLocalizedString("Delete", comment: "Delete"),
        isDestructive: true,
        cancelAction: NSLocalizedString("Cancel", comment: "Cancel"),
        presentingController: self)
    delete.addCondition(confirmation)
    queue.addOperation(delete)
}
```

When this delete operation is added to the queue, the user will be presented with a standard system `UIAlertController` asking if they're sure. Additionally, other `AlertOperation` instances will be prevented from running.

The above “save contact” operation looks quite verbose for though for a such a simple task. Luckily in reality we can do this:

```swift
let save = ComposedOperation(connection.writeOperation(contact))
save.addObserver(BlockObserver { (_, errors) in
    print(“Did save contact”)
})
queue.addOperation(save)
```

Because sometimes creating an `Operation` subclass is a little heavy handed. Above we composed an existing `NSOperation` but we can utilize a `BlockOperation`. For example, let say we want to warn the user before they cancel a "Add New Contact" controller without saving the Contact. 

```swift
@IBAction didTapCancelButton(button: UIButton) {
    dismiss()
}

func dismiss() {
    // Define a dispatch block for unwinding.
    let dismiss = {
        self.performSegueWithIdentifier(SegueIdentifier.UnwindToContacts.rawValue, sender: nil)
    }

    // Wrap this in a block operation
    let operation = BlockOperation(mainQueueBlock: dismiss)

    // Attach a condition to check if there are unsaved changes
    // this is an imaginary conditon - doesn't exist in Operation framework
    let condition = UnsavedChangesCondition(
        connection: connection,
        value: contact,
        save: save(dismiss),
        discard: BlockOperation(mainQueueBlock: dismiss),
        presenter: self
    )
    operation.addCondition(condition)

    // Attach an observer to see if the operation failed because
    // there were no edits from a default Contact - in which case
    // continue with dismissing the controller.
    operation.addObserver(BlockObserver { [unowned queue] (_, errors) in
        if let error = errors.first as? UnsavedChangesConditionError {
            switch error {
            case .NoChangesFromDefault:
                queue.addOperation(BlockOperation(mainQueueBlock: dismiss))

            case .HasUnsavedChanges:
                break
            }
        }
    })

    queue.addOperation(operation)
}

```

In the above example, we're able to compose reusable (and testable!) units of work in order to express relatively complex control logic. Another way to achieve this kind of behaviour might be through FRP techniques, however those are unlikely to yield re-usable types like `UnsavedChangesCondition`, or even `DismissController` if the above was composed inside a custom `GroupOperation`.

## Device & OS Permissions

Requesting permissions from the user can often be a relatively complex task, which almost all apps have to perform at some point. Often developers put requests for these permissions in their AppDelegate, meaning that new users are bombarded with alerts. This isn't a great experience, and Apple expressly suggest only requesting permissions when you need them. However, this is easier said than done. The Operations framework can help however. Lets say we want to get the user's current location.

```swift
func getCurrentLocation(completion: CLLocation -> Void) {
    queue.addOperation(UserLocationOperation(handler: completion))
}
```

This operation will automatically request the user's permission if the application doesn't already have the required authorization, the default is "when in use".

Perhaps also you want to just test to see if authorization has already been granted, but not ask for it if it hasn't. This can be done using a `BlockOperation` and `SilentCondition`. In Apple’s original sample code from WWDC 2015, there are a number of OperationConditions which express the authorization status for device or OS permissions. Things like, `LocationCondition`, and `HealthCondition`. In version 2.3 of Operations I moved away from this model to unify this functionality into `CapabilityType` protocol. Where previously there were bespoke conditions (and errors) to test the status, there is now a single condition, which is initialized with a `CapabilityType`. For example this operation lets you silently test the current status of the location capabilities.

```swift
queue.addOperation(GetAuthorizationStatus(Capability.Location(.WhenInUse)) { enabled, status in 
    switch (enabled, status) {
        case (false, _):
           // Location services are not enabled
        case (true, .NotDetermined):
           // Location services are enabled, but not currently determined for the app.
    }
})
```

To explicitly request permission, use the `Authorize` operation,:

```swift
queue.addOperation(Authorize(Capability.Location(.WhenInUse)) { enabled, status in 
    switch (enabled, status) {
        case (false, _):
           // Location services are not enabled
        case (true, .NotDetermined):
           // Location services are enabled, but not currently determined for the app.
    }
})
```

Note that `Authorize` is a subclass, and has exactly the same initializer, meaning that you can implement a function for this.

```swift
func locationStatusDidChange(enabled: Bool, status: CLAuthorizationStatus) {
    switch (enabled, status) {
        case (false, _):
           // Location services are not enabled
        case (true, .NotDetermined):
           // Location services are enabled, but not currently determined for the app.
    }
}
```

To express the allow permissions in an `OperationCondition`, use `AuthorizedFor` in exactly the same way.

```swift
let operation = MyOperation()
operation.addCondition(AuthorizedFor(Capability.Location(.WhenInUse)))
queue.addOperation(operation)
```

## Installation

Operations is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod ‘Operations’
```

For Swift 2.0, add the following to your Podfile:

```ruby
pod ‘Operations’, :git => ‘https://github.com/danthorpe/Operations.git', :branch => ‘swift_2.0’
```

## Features

This is a brief summary of the current and planned functionality.

### Foundation

- [x] `Operation` and `OperationQueue` class definitions.
- [x] `OperationCondition` and evaluator functionality.
- [x] `OperationObserver` definition and integration.

### Building Blocks

- [x] `MutuallyExclusive` condition e.g. can only one `AlertPresentation` at once.
- [x] `NegatedCondition` evaluates the reverse of the composed condition.
- [x] `SilentCondition` suppress any dependencies of the composed condition.
- [x] ~~`NoCancelledDependencies`~~ `NoFailedDependenciesCondition` requires that all dependencies succeeded.
- [x] `BlockObserver` run blocks when the attached operation starts, produces another operation or finishes.
- [x] `BackgroundObserver` automatically start and stop background tasks if the application enters the background while the attached operation is running.
- [x] `NetworkObserver` automatically manage the device’s network indicator while the operation is running.
- [x] `TimeoutObserver` automatically cancel the attached operation if the timeout interval is reached.
- [x] `LoggingObserver` enable simple logging of the lifecycle of the operation and any of it’s produced operations.
- [x] `GroupOperation` encapsulate multiple operations into their own discrete unit, running on their own queue. Supports internally adding new operations, so can be used for batch processing or greedy operation tasks.
- [x] `DelayOperation` inserts a delay into the operation queue.
- [x] `BlockOperation` run a block inside an `Operation`. Supports unsuccessful finishing.
- [x] `GatedOperation` only run the composed operation if the provided block evaluates true.
- [x] `ComposedOperation` run a composed `NSOperation`. This is great for adding conditions or observers to bog-standard `NSOperation`s without having to subclass them. 

### Features

- [x] `GetAuthorizationStatus` get the current authorization status for the given `CapabilityType`. Supports EventKit, CloudKit, HealthKit, CoreLocation, PassKit, Photos.
- [x] `Authorize` request the required permissions to access the required `CapabilityType`. Supports EventKit, CloudKit, HealthKit, CoreLocation, PassKit, Photos.
- [x] `AuthorizedFor` express the required permissions to access the required `CapabilityType` as an `OperationCondition`. Meaning that if the status has not been determined yet, it will trigger authorization. Supports EventKit, CloudKit, HealthKit, CoreLocation, PassKit, Photos.
- [x] `ReachabilityCondition` requires that the supplied URL is reachable.
- [x] `ReachableOperation` compose an operation which must complete and requires network reachability. This uses an included system  Reachability object and does not require any extra dependencies. However currently in Swift 1.2, as function pointers are not supported, this uses a polling mechanism with `dispatch_source_timer`. I will probably replace this with more efficient Objective-C soon.
- [x] `CloudKitOperation` compose a `CKDatabaseOperation` inside an `Operation` with the appropriate `CKDatabase`.
- [x] `UserLocationOperation` access the user’s current location with desired accuracy. 
- [x] `ReverseGeocodeOperation` perform a reverse geocode lookup of the supplied `CLLocation`.
- [x] `ReverseGeocodeUserLocationOperation` perform a reverse geocode lookup of user’s current location.  
- [x] `UserNotificationCondition` require that the user has granted permission to present notifications.
- [x] `RemoteNotificationCondition` require that the user has granted permissions to receive remote notifications.
- [x] `UserConfirmationCondition` requires that the user confirms an action presented to them using a `UIAlertController`. The condition is configurable for title, message and button texts. 
- [x] `WebpageOperation` given a URL, will present a `SFSafariViewController`.

### +AddressBook

Available as a subspec (if using CocoaPods) is `ABAddressBook.framework` related operations.

- [x] `AddressBookCondition` require authorized access to ABAddressBook. Will automatically request access if status is not already determined.
- [x] `AddressBookOperation` is a base operation which creates the address book and requests access.
- [x] `AddressBookGetResource` is a subclass of `AddressBookOperation` and exposes methods to access resources from the address book. These can include person records and groups. All resources are wrapped inside Swift facades to the underlying opaque AddressBook types.
- [x] `AddressBookGetGroup` will get the group for a given name.
- [x] `AddressBookCreateGroup` will create the group for a given name, if it doesn’t already exist.
- [x] `AddressBookRemoveGroup` will remove the group for a given name.
- [x] `AddressBookAddPersonToGroup` will add the person with record id to the group with the provided name.
- [x] `AddressBookRemovePersonFromGroup` will remove the person with record id from the group with the provided name.
- [x] `AddressBookMapPeople<T>` takes an optional group name, and a mapping transform. It will map all the people in the address book (or in the group) via the transform. This is great if you have your own representation of a Person, and which to import the AddressBook. In such a case, create the following:

```swift
extension MyPerson {
    init?(addressBookPerson: AddressBookPerson) {
        // Create a person, return nil if not possible.
    }
}
```

Then, import people

```swift
let getPeople = AddressBookMapPeople { MyPerson($0) }
queue.addOperation(getPeople)
```

Use an observer or `GroupOperation` to access the results via the map operation’s `results` property.

- [x] `AddressBookDisplayPersonViewController` is an operation which will display a person (provided their record id), from a controller in your app. This operation will perform the necessary address book tasks. It can present the controller using 3 different styles, either `.Present` (i.e. modal), `.Show` (i.e. old style push) or `.ShowDetail`. Here’s an example:

```swift
    func displayPersonWithAddressBookRecordID(recordID: ABRecordID) {
        let controller = ABPersonViewController()
        controller.allowsActions = true
        controller.allowsEditing = true
        controller.shouldShowLinkedPeople = true
        let show = AddressBookDisplayPersonViewController(
						personViewController: controller, 
						personWithID: recordID, 
						displayControllerFrom: .ShowDetail(self), 
						delegate: self
				)
        queue.addOperation(show)
    }
```
- [x] `AddressBookDisplayNewPersonViewController` same as the above, but for showing the standard create new person controller. For example:

```swift
    @IBAction func didTapAddNewPerson(sender: UIBarButtonItem) {
        let show = AddressBookDisplayNewPersonViewController(
					displayControllerFrom: .Present(self), 
					delegate: self, 
					addToGroupWithName: “Special People”
				)
        queue.addOperation(show)
    }
```


## Motivation

I want to stress that this code is heavily influenced by Apple. In no way am I attempting to assume any sort of credit for this architecture - that goes to [Dave DeLong](https://twitter.com/davedelong) and his team. My motivations are that I want to adopt this code in my own projects, and so require a solid well tested framework which I can integrate with.

