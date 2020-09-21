//
//  MLSignalStore.h
//  Monal
//
//  Created by Anurodh Pokharel on 5/3/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
@import SignalProtocolObjC;

@interface MLSignalStore : NSObject <SignalStore>
@property (nonatomic, assign) u_int32_t deviceid;
@property (nonatomic, strong) SignalIdentityKeyPair *identityKeyPair;
@property (nonatomic, strong) SignalSignedPreKey *signedPreKey;
@property (nonatomic, strong) NSArray<SignalPreKey*>* preKeys;

-(id) initWithAccountId:(NSString *) accountId;
-(void) saveValues;

-(NSData *) getIdentityForAddress:(SignalAddress*)address;
/**
 all devices even those without sessions
 */
- (NSArray<NSNumber*>*) knownDevicesForAddressName:(NSString*)addressName;
-(NSMutableArray *) readPreKeys;
-(void) updateTrust:(BOOL) trust forAddress:(SignalAddress*)address;
-(void) deleteDeviceforAddress:(SignalAddress*)address;
-(void) deletePreKeyWithRid:(NSNumber*) rid;

-(int) getHighestPreyKeyId;
-(int) getPreKeyCount;


@end
