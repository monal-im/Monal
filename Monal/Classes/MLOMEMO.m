//
//  MLOMEMO.m
//  Monal
//
//  Created by Friedrich Altheide on 21.06.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLOMEMO.h"
#import "SignalAddress.h"
#import "MLSignalStore.h"
#import "SignalContext.h"
#import "AESGcm.h"
#import "HelperTools.h"
#import "XMPPIQ.h"
#import "xmpp.h"
#import "ParseIq.h"


@interface MLOMEMO ()

@property (atomic, strong) SignalContext* _signalContext;

// TODO: rename senderJID to accountJid
@property (nonatomic, strong) NSString* _senderJid;
@property (nonatomic, strong) NSString* _accountRessource;
@property (nonatomic, strong) NSString* _accountNo;
@property (nonatomic, strong) MLXMPPConnection* _connection;

@property (nonatomic, strong) xmpp* xmppConnection;
@end

static const size_t MIN_OMEMO_KEYS = 25;
static const size_t MAX_OMEMO_KEYS = 120;

@implementation MLOMEMO

-(MLOMEMO *) initWithAccount:(NSString *) accountNo jid:(NSString *) jid ressource:(NSString*) ressource connectionProps:(MLXMPPConnection *) connectionProps xmppConnection:(xmpp*) xmppConnection
{
    self = [super init];
    self->signalLock = [NSLock new];
    self._senderJid = jid;
    self._accountRessource = ressource;
    self._accountNo = accountNo;
    self._connection = connectionProps;
    self.xmppConnection = xmppConnection;

    [self setupSignal];

    return self;
}

-(void) setupSignal
{
    self.monalSignalStore = [[MLSignalStore alloc] initWithAccountId:self._accountNo];

    // signal store
    SignalStorage* signalStorage = [[SignalStorage alloc] initWithSignalStore:self.monalSignalStore];
    // signal context
    self._signalContext = [[SignalContext alloc] initWithStorage:signalStorage];
    // signal helper
    SignalKeyHelper* signalHelper = [[SignalKeyHelper alloc] initWithContext:self._signalContext];

    if(self.monalSignalStore.deviceid == 0)
    {
        // Generate a new device id
        // TODO: check if device id is unique
        self.monalSignalStore.deviceid = [signalHelper generateRegistrationId];
        // Create identity key pair
        self.monalSignalStore.identityKeyPair = [signalHelper generateIdentityKeyPair];
        self.monalSignalStore.signedPreKey = [signalHelper generateSignedPreKeyWithIdentity:self.monalSignalStore.identityKeyPair signedPreKeyId:1];
        // Generate single use keys
        [self generateNewKeysIfNeeded];
        [self sendOMEMOBundle];

        SignalAddress* address = [[SignalAddress alloc] initWithName:self._senderJid deviceId:self.monalSignalStore.deviceid];
        [self.monalSignalStore saveIdentity:address identityKey:self.monalSignalStore.identityKeyPair.publicKey];

        // request own omemo device list -> we will add our new device automatilcy as we are missing in the list
        [self queryOMEMODevicesFrom:self._senderJid];
        // FIXME: query queryOMEMODevicesFrom after connected -> state change
    }
}

-(void) sendOMEMOBundle
{
    if(!self._connection.supportsPubSub || (self.xmppConnection.accountState < kStateBound && ![self.xmppConnection isHibernated])) return;
    NSString* deviceid = [NSString stringWithFormat:@"%d", self.monalSignalStore.deviceid];
    XMPPIQ* signalKeys = [[XMPPIQ alloc] initWithType:kiqSetType];
    [signalKeys publishKeys:@{@"signedPreKeyPublic":self.monalSignalStore.signedPreKey.keyPair.publicKey, @"signedPreKeySignature":self.monalSignalStore.signedPreKey.signature, @"identityKey":self.monalSignalStore.identityKeyPair.publicKey, @"signedPreKeyId": [NSString stringWithFormat:@"%d",self.monalSignalStore.signedPreKey.preKeyId]} andPreKeys:self.monalSignalStore.preKeys withDeviceId:deviceid];
    [signalKeys.attributes setValue:[NSString stringWithFormat:@"%@/%@", self._senderJid, self._accountRessource] forKey:@"from"];

    if(self.xmppConnection) [self.xmppConnection send:signalKeys];
}

-(void) subscribeOMEMODevicesFrom:(NSString *) jid
{
    if(!self._connection.supportsPubSub || (self.xmppConnection.accountState < kStateBound && ![self.xmppConnection isHibernated])) return;
    XMPPIQ* query = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
    [query setiqTo:self._senderJid];
    [query subscribeDevices:jid];
    if(self.xmppConnection) [self.xmppConnection send:query];
}

-(void) queryOMEMODevicesFrom:(NSString *) jid
{
    if(!self._connection.supportsPubSub || (self.xmppConnection.accountState < kStateBound && ![self.xmppConnection isHibernated])) return;
    XMPPIQ* query = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqGetType];
    [query setiqTo:jid];
    [query requestDevices];
    if([jid isEqualToString:self._senderJid]) {
        // save our own last omemo query id for matching against our own device list received from the server
        self.deviceQueryId = [query.attributes objectForKey:@"id"];
    }

    if(self.xmppConnection) [self.xmppConnection send:query];
}

/*
 * generates new omemo keys if we have less than MIN_OMEMO_KEYS left
 */
-(void) generateNewKeysIfNeeded
{
    // generate new keys if less than MIN_OMEMO_KEYS are available
    int preKeyCount = [self.monalSignalStore getPreKeyCount];
    if(preKeyCount < MIN_OMEMO_KEYS) {
        SignalKeyHelper* signalHelper = [[SignalKeyHelper alloc] initWithContext:self._signalContext];

        // Generate new keys so that we have a total of MAX_OMEMO_KEYS keys again
        int lastPreyKedId = [self.monalSignalStore getHighestPreyKeyId];
        size_t cntKeysNeeded = MAX_OMEMO_KEYS - preKeyCount;
        // Start generating with keyId > last send key id
        self.monalSignalStore.preKeys = [signalHelper generatePreKeysWithStartingPreKeyId:(lastPreyKedId + 1) count:cntKeysNeeded];
        [self.monalSignalStore saveValues];

        // send out new omemo bundle
        [self sendOMEMOBundle];
    }
}

-(void) queryOMEMOBundleFrom:(NSString *) jid andDevice:(NSString *) deviceid
{
    if(!self._connection.supportsPubSub || (self.xmppConnection.accountState < kStateBound && ![self.xmppConnection isHibernated])) return;
    XMPPIQ* bundleQuery = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqGetType];
    [bundleQuery setiqTo:jid];
    [bundleQuery requestBundles:deviceid];

    if(self.xmppConnection) [self.xmppConnection send:bundleQuery];
}

-(void) processOMEMODevices:(NSArray<NSString*>*) receivedDevicesStr from:(NSString *) source
{
    // convert device ids to NSNumber array
    NSMutableSet<NSNumber*>* receivedDevices = [[NSMutableSet alloc] init];
    for(NSString* device in receivedDevicesStr) {
        [receivedDevices addObject:[NSNumber numberWithInt:device.intValue]];
    }
    if(receivedDevices)
    {
        NSAssert(self._senderJid == self._connection.identity.jid, @"connection jid should be equal to the senderJid");

        NSArray<NSNumber*>* existingDevices = [self.monalSignalStore knownDevicesForAddressName:source];

        // query omemo bundles from devices that are not in our signalStorage
        // TODO: queryOMEMOBundleFrom when sending first msg without session
        for(NSNumber* deviceId in receivedDevices) {
            if(![existingDevices containsObject:deviceId]) {
                [self queryOMEMOBundleFrom:source andDevice:[deviceId stringValue]];
            }
        }

        // remove devices from our signalStorage when they are no longer published
        for(NSNumber* deviceId in existingDevices) {
            if(![receivedDevices containsObject:deviceId]) {
                // only delete other devices from signal store && keep our own entry
                if(!([source isEqualToString:self._senderJid] && deviceId.intValue == self.monalSignalStore.deviceid))
                    [self deleteDeviceForSource:source andRid:deviceId.intValue];
            }
        };

        // Send our own device id when it is missing on the server
        if(!source || [source isEqualToString:self._senderJid])
        {
            [self sendOMEMODevice:receivedDevices force:NO];
        }
    }
}

-(BOOL) knownDevicesForAddressNameExist:(NSString*) addressName
{
    return ([[self.monalSignalStore knownDevicesForAddressName:addressName] count] > 0);
}

-(NSArray<NSNumber*>*) knownDevicesForAddressName:(NSString*) addressName
{
    return [self.monalSignalStore knownDevicesForAddressName:addressName];
}

-(void) deleteDeviceForSource:(NSString*) source andRid:(int) rid
{
    SignalAddress* address = [[SignalAddress alloc] initWithName:source deviceId:rid];
    [self.monalSignalStore deleteDeviceforAddress:address];
}

-(BOOL) isTrustedIdentity:(SignalAddress*)address identityKey:(NSData*)identityKey
{
    return [self.monalSignalStore isTrustedIdentity:address identityKey:identityKey];
}

-(void) updateTrust:(BOOL) trust forAddress:(SignalAddress*)address
{
    [self.monalSignalStore updateTrust:trust forAddress:address];
}

-(NSData *) getIdentityForAddress:(SignalAddress*)address
{
    return [self.monalSignalStore getIdentityForAddress:address];
}



-(void) sendOMEMODeviceWithForce:(BOOL) force
{
    NSArray* ownCachedDevices = [self knownDevicesForAddressName:self._senderJid];
    NSSet<NSNumber*>* ownCachedDevicesSet = [[NSSet alloc] initWithArray:ownCachedDevices];
    [self sendOMEMODevice:ownCachedDevicesSet force:force];
}

-(void) sendOMEMODevice:(NSSet<NSNumber*>*) receivedDevices force:(BOOL) force
{
    if(!self._connection.supportsPubSub || (self.xmppConnection.accountState < kStateBound && ![self.xmppConnection isHibernated])) return;
    NSMutableSet<NSNumber*>* devices = [[NSMutableSet alloc] init];
    if(receivedDevices && [receivedDevices count] > 0) {
        [devices unionSet:receivedDevices];
    }

    // Check if our own device string is already in our set
    if(![devices containsObject:[NSNumber numberWithInt:self.monalSignalStore.deviceid]] || force)
    {
        [devices addObject:[NSNumber numberWithInt:self.monalSignalStore.deviceid]];

        XMPPIQ* signalDevice = [[XMPPIQ alloc] initWithType:kiqSetType];
        [signalDevice publishDevices:devices];
        if(self.xmppConnection) [self.xmppConnection send:signalDevice];
    }
}

-(void) processOMEMOKeys:(ParseIq *) iqNode
{
    if(iqNode.signedPreKeyPublic && self._signalContext)
    {
        NSString* source = iqNode.from;
        if(!source)
        {
            source = self._senderJid;
        }

        uint32_t device = (uint32_t)[iqNode.deviceid intValue];
        if(!iqNode.deviceid) return;

        SignalAddress* address = [[SignalAddress alloc] initWithName:source deviceId:device];
        SignalSessionBuilder* builder = [[SignalSessionBuilder alloc] initWithAddress:address context:self._signalContext];

        [iqNode.preKeys enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary* row = (NSDictionary *) obj;
            NSString* keyid = (NSString *)[row objectForKey:@"preKeyId"];
            NSData* preKeyData = [HelperTools dataWithBase64EncodedString:[row objectForKey:@"preKey"]];
            if(preKeyData) {
                SignalPreKeyBundle *bundle = [[SignalPreKeyBundle alloc] initWithRegistrationId:0
                                                                                deviceId:device
                                                                                       preKeyId:[keyid intValue]
                                                                                   preKeyPublic:preKeyData
                                                                                 signedPreKeyId:iqNode.signedPreKeyId.intValue
                                                                             signedPreKeyPublic:[HelperTools dataWithBase64EncodedString:iqNode.signedPreKeyPublic]
                                                                                      signature:[HelperTools dataWithBase64EncodedString:iqNode.signedPreKeySignature]
                                                                                    identityKey:[HelperTools dataWithBase64EncodedString:iqNode.identityKey]
                                                                                          error:nil];
                [builder processPreKeyBundle:bundle error:nil];
            } else  {
                DDLogError(@"Could not decode base64 prekey %@", row);
            }
        }];
    }
}

-(void) addEncryptionKeyForAllDevices:(NSArray*) devices encryptForJid:(NSString*) encryptForJid withEncryptedPayload:(MLEncryptedPayload*) encryptedPayload withXMLHeader:(MLXMLNode*) xmlHeader {
    // Encrypt message for all devices known from the recipient
    [devices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSNumber* device = (NSNumber *)obj;
        SignalAddress* address = [[SignalAddress alloc] initWithName:encryptForJid deviceId:(uint32_t)device.intValue];

        NSData* identity = [self.monalSignalStore getIdentityForAddress:address];

        // Only add encryption key for devices that are trusted
        if([self.monalSignalStore isTrustedIdentity:address identityKey:identity]) {
            SignalSessionCipher* cipher = [[SignalSessionCipher alloc] initWithAddress:address context:self._signalContext];
            NSError* error;
            SignalCiphertext* deviceEncryptedKey = [cipher encryptData:encryptedPayload.key error:&error];

            MLXMLNode* keyNode = [[MLXMLNode alloc] initWithElement:@"key"];
            [keyNode.attributes setObject:[NSString stringWithFormat:@"%@", device] forKey:@"rid"];
            if(deviceEncryptedKey.type == SignalCiphertextTypePreKeyMessage)
            {
                [keyNode.attributes setObject:@"1" forKey:@"prekey"];
            }

            [keyNode setData:[HelperTools encodeBase64WithData:deviceEncryptedKey.data]];
            [xmlHeader.children addObject:keyNode];
        }
    }];
}

-(void) encryptMessage:(XMPPMessage*) messageNode withMessage:(NSString*) message toContact:(NSString*) toContact
{
    NSAssert(self._signalContext, @"_signalContext should be inited.");

    [messageNode setBody:NSLocalizedString(@"[This message is OMEMO encrypted]", @"")];

    NSArray* devices = [self.monalSignalStore allDeviceIdsForAddressName:toContact];
    NSArray* myDevices = [self.monalSignalStore allDeviceIdsForAddressName:self._senderJid];

    // Check if we found omemo keys from the recipient
    if(devices.count > 0) {
        NSData* messageBytes = [message dataUsingEncoding:NSUTF8StringEncoding];

        // Encrypt message
        MLEncryptedPayload* encryptedPayload = [AESGcm encrypt:messageBytes keySize:16];

        MLXMLNode* encrypted = [[MLXMLNode alloc] initWithElement:@"encrypted"];
        [encrypted.attributes setObject:@"eu.siacs.conversations.axolotl" forKey:kXMLNS];
        [messageNode.children addObject:encrypted];

        MLXMLNode* payload = [[MLXMLNode alloc] initWithElement:@"payload"];
        [payload setData:[HelperTools encodeBase64WithData:encryptedPayload.body]];
        [encrypted.children addObject:payload];

        // Get own device id
        NSString* deviceid = [NSString stringWithFormat:@"%d",self.monalSignalStore.deviceid];
        MLXMLNode* header = [[MLXMLNode alloc] initWithElement:@"header"];
        [header.attributes setObject:deviceid forKey:@"sid"];
        [encrypted.children addObject:header];

        MLXMLNode* ivNode =[[MLXMLNode alloc] initWithElement:@"iv"];
        [ivNode setData:[HelperTools encodeBase64WithData:encryptedPayload.iv]];
        [header.children addObject:ivNode];

        [self addEncryptionKeyForAllDevices:devices encryptForJid:toContact withEncryptedPayload:encryptedPayload withXMLHeader:header];

        [self addEncryptionKeyForAllDevices:myDevices encryptForJid:self._senderJid withEncryptedPayload:encryptedPayload withXMLHeader:header];
    }
}

-(NSString *) decryptMessage:(ParseMessage *) messageNode
{
    if(!messageNode.encryptedPayload) {
        DDLogDebug(@"DecrypMessage called but the message is not encrypted");
        return nil;
    }

    [self->signalLock lock];

    SignalAddress* address = [[SignalAddress alloc] initWithName:messageNode.from.lowercaseString deviceId:(uint32_t)messageNode.sid.intValue];
    if(!self._signalContext) {
        DDLogError(@"Missing signal context");
        [self->signalLock unlock];
        return NSLocalizedString(@"Error decrypting message", @"");
    }

    NSDictionary* messageKey;
    for(NSDictionary* currentKey in messageNode.signalKeys) {
        NSString* rid = [currentKey objectForKey:@"rid"];
        if(rid.intValue == self.monalSignalStore.deviceid)
        {
            messageKey = currentKey;
            break;
        }
    };
    if(!messageKey)
    {
        DDLogError(@"Message was not encrypted for this device: %d", self.monalSignalStore.deviceid);
        [self->signalLock unlock];
        return [NSString stringWithFormat:NSLocalizedString(@"Message was not encrypted for this device. Please make sure the sender trusts deviceid %d and that they have you as a contact.", @""), self.monalSignalStore.deviceid];
    } else {
        SignalSessionCipher* cipher = [[SignalSessionCipher alloc] initWithAddress:address context:self._signalContext];
        SignalCiphertextType messagetype;

        // Check if message is encrypted with a prekey
        if([[messageKey objectForKey:@"prekey"] isEqualToString:@"1"])
        {
            messagetype = SignalCiphertextTypePreKeyMessage;
        } else  {
            messagetype = SignalCiphertextTypeMessage;
        }

        NSData* decoded = [HelperTools dataWithBase64EncodedString:[messageKey objectForKey:@"key"]];

        SignalCiphertext* ciphertext = [[SignalCiphertext alloc] initWithData:decoded type:messagetype];
        NSError* error;
        NSData* decryptedKey = [cipher decryptCiphertext:ciphertext error:&error];
        if(error) {
            DDLogError(@"Could not decrypt to obtain key: %@", error);
            [self->signalLock unlock];
            return [NSString stringWithFormat:@"There was an error decrypting this encrypted message (Signal error). To resolve this, try sending an encrypted message to this person. (%@)", error];
        }
        NSData* key;
        NSData* auth;

        if(messagetype == SignalCiphertextTypePreKeyMessage)
        {
            [self generateNewKeysIfNeeded];
            // TODO: remove key with rid from our bundle
            // TODO: repulish own keys
        }

        if(!decryptedKey){
            DDLogError(@"Could not decrypt to obtain key.");
            [self->signalLock unlock];
            return NSLocalizedString(@"There was an error decrypting this encrypted message (Signal error). To resolve this, try sending an encrypted message to this person.", @"");
        }
        else  {
            if(decryptedKey.length == 16 * 2)
            {
                key = [decryptedKey subdataWithRange:NSMakeRange(0, 16)];
                auth = [decryptedKey subdataWithRange:NSMakeRange(16, 16)];
            }
            else {
                key = decryptedKey;
            }
            if(key){
                NSData* iv = [HelperTools dataWithBase64EncodedString:messageNode.iv];
                NSData* decodedPayload = [HelperTools dataWithBase64EncodedString:messageNode.encryptedPayload];

                NSData* decData = [AESGcm decrypt:decodedPayload withKey:key andIv:iv withAuth:auth];
                if(!decData) {
                    DDLogError(@"Could not decrypt message with key that was decrypted.");
                    [self->signalLock unlock];
                     return NSLocalizedString(@"Encrypted message was sent in an older format Monal can't decrypt. Please ask them to update their client. (GCM error)", @"");
                }
                else  {
                    DDLogInfo(@"Decrypted message passing bask string.");
                }
                NSString* messageString = [[NSString alloc] initWithData:decData encoding:NSUTF8StringEncoding];
                [self->signalLock unlock];
                return messageString;
            } else  {
                DDLogError(@"Could not get key");
                [self->signalLock unlock];
                return NSLocalizedString(@"Could not decrypt message", @"");
            }
        }
    }
}

@end
