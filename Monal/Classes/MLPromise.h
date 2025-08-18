//
//  MLPromise.h
//  Monal
//
//  Created by Matthew Fennell on 29/09/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

/**
 In Monal, we use the handler framework to create "serializable callbacks" so that processing can be handed off between the main app and app extension.
 (See https://github.com/monal-im/Monal/wiki/Handler-Framework/ for more information).
 Meanwhile, in SwiftUI, we use AnyPromises (aka PMKResolvers) to update the state of the UI as a result of an asynchronous action.

 If an async action that should trigger a UI update gets started from the main app, but then the app is put into the background, the handler for that action will get called from the app extension. The UI should reflect the new state when the app is reopened.
 Critically, the main app and app extension are separate processes and do not share memory, so we need a way to co-ordinate them.

 This class handle this co-ordination via the database. Any function that creates a handler to respond to the response from the server, but returns an AnyPromise to the UI, could create an MLPromise, call toAnyPromise on it to return an AnyPromise to the UI, then pass the MLPromise instance to the handler. Then, the handler can fulfill or reject the promise, and the MLPromise will take care of updating the UI.

 Meanwhile, the MLPromise takes care of:
 * Co-ordinating whether the promise has been fulfilled, and its value, between the main app and app extension (via the database)
 * Checking when the main app reopens whether the app extension had fulfilled a promise in the meantime, and then calling the AnyPromise for the UI
 */
@interface MLPromise : NSObject<NSSecureCoding>

@property(nonatomic, strong) NSUUID* uuid;

-(void) fulfill:(id _Nullable) arg;
-(void) rejectWithError:(NSError*) error andNode:(XMPPStanza* _Nullable) node forAccountWithID:(NSNumber*) accountID;
-(AnyPromise*) toAnyPromise;

+(void) consumeStalePromises;

@end

@interface MLPromiseRejection : NSObject<NSSecureCoding>

@end

NS_ASSUME_NONNULL_END
