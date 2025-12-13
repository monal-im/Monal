//
//  HT.m
//  monalxmpp
//
//  Created by Thilo Molitor on 11.12.25.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/HT.h>

@interface HT ()
{
    BOOL _usingChannelBinding;
    NSString* _method;
    NSString* _channelBinding;
    NSString* _username;
    NSString* _token;
    NSData* _Nullable _channelBindingData;
    
    BOOL _initiatorMessageGenerated;
}
@end

@implementation HT

//list supported mechanisms (highest security first!)
+(NSArray*) supportedMechanismsIncludingChannelBinding:(BOOL) include
{
    //we don't support FAST mechanisms without channel-binding
    if(include)
        //only support exporter channel-binding: lower channel-bindings pose a security risk yet to be solved (dubbed upgrade prevention)
        return @[@"HT-SHA-512-EXPR", @"HT-SHA-256-EXPR"];
        //return @[@"HT-SHA-512-EXPR", @"HT-SHA-256-EXPR", @"HT-SHA-512-ENDP", @"HT-SHA-256-ENDP"];
    return @[];
    
//     if(include)
//         return @[@"HT-SHA-512-EXPR", @"HT-SHA-256-EXPR", @"HT-SHA-512-ENDP", @"HT-SHA-256-ENDP", @"HT-SHA-512-NONE", @"HT-SHA-256-NONE"];
//     return @[@"HT-SHA-512-NONE", @"HT-SHA-256-NONE"];
}
-(instancetype) initWithUsername:(NSString*) username token:(NSString*) token method:(NSString*) method andChannelBindingData:(NSData* _Nullable) channelBindingData
{
    self = [super init];
    MLAssert([[[self class] supportedMechanismsIncludingChannelBinding:YES] containsObject:method], @"Unsupported HT hash method!", (@{@"method": nilWrapper(method)}));
    _usingChannelBinding = ![@"-NONE" isEqualToString:[method substringFromIndex:method.length-5]];
    _method = [method substringWithRange:NSMakeRange(3, method.length-3-5)];
    _channelBinding = [method substringWithRange:NSMakeRange(method.length-4, 4)];
    _username = username;
    _token = token;
    _channelBindingData = channelBindingData;
    _finishedSuccessfully = NO;
    _initiatorMessageGenerated = NO;
    return self;
}

-(NSData*) initiatorMessage
{
    MLAssert(!_finishedSuccessfully, @"HT handler finished already!");
    MLAssert(!_initiatorMessageGenerated, @"HT handler already generated initiator message!");
    
    NSMutableData* initiatorConstantWithChannelBindingData = [NSMutableData new];
    [initiatorConstantWithChannelBindingData appendData:[@"Initiator" dataUsingEncoding:NSUTF8StringEncoding]];
    if(_usingChannelBinding && _channelBindingData != nil)
        [initiatorConstantWithChannelBindingData appendData:_channelBindingData];
    
    NSMutableData* initiatorMessage = [NSMutableData new];
    [initiatorMessage appendData:[[NSString stringWithFormat:@"%@\0", _username] dataUsingEncoding:NSUTF8StringEncoding]];
    [initiatorMessage appendData:[self hmacForKey:[_token dataUsingEncoding:NSUTF8StringEncoding] andData:initiatorConstantWithChannelBindingData]];
    return initiatorMessage;
}

-(MLHtStatus) parseResponderMessage:(NSData*) message
{
    MLAssert(!_finishedSuccessfully, @"HT handler finished already!");
    
    //old draft-schmaus-kitten-sasl-ht-09 version without 0x00/0x01 prefix as still used by prosody and ejabberd
    //TODO: remove as soon as those servers are updated and use the new version below instead
    if(![self checkResponseData:message])
        return MLHtStatusResponderSignatureError;
    
    _finishedSuccessfully = YES;
    return MLHtStatusResponderMessageOK;
    
    /*
    NSData* data = [message subdataWithRange:NSMakeRange(1, message.length-1)];
    if(*((uint8_t*)message.bytes) == '\1')
    {
        NSString* errorMessage = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        DDLogError(@"Got HT error string: %@", errorMessage);
        return MLHtStatusResponderMessageError;
    }
    else if(*((uint8_t*)message.bytes) == '\0')
    {
        if(![self checkResponseData:data])
            return MLHtStatusResponderSignatureError;
        
        _finishedSuccessfully = YES;
        return MLHtStatusResponderMessageOK;
    }
    DDLogError(@"Server implementation error: first HT byte not 0x00 or 0x01!");
    return MLHtStatusResponderMessageError;
    */
}

-(BOOL) checkResponseData:(NSData*) data
{
    NSMutableData* responderConstantWithChannelBindingData = [NSMutableData new];
    [responderConstantWithChannelBindingData appendData:[@"Responder" dataUsingEncoding:NSUTF8StringEncoding]];
    if(_usingChannelBinding && _channelBindingData != nil)
        [responderConstantWithChannelBindingData appendData:_channelBindingData];
    
    NSData* expectedResponderData = [self hmacForKey:[_token dataUsingEncoding:NSUTF8StringEncoding] andData:responderConstantWithChannelBindingData];
    DDLogVerbose(@"Checking fast signature remote: %@ local: %@ rawValue: %@", data, expectedResponderData, responderConstantWithChannelBindingData);
    return [HelperTools constantTimeCompareAttackerData:data withKnownData:expectedResponderData];
}

-(NSString*) method
{
    return [NSString stringWithFormat:@"HT-%@-%@", _method, _channelBinding];
}

-(NSData*) hmacForKey:(NSData*) key andData:(NSData*) data
{
    if([_method isEqualToString:@"SHA-256"])
        return [HelperTools sha256HmacForKey:key andData:data];
    if([_method isEqualToString:@"SHA-512"])
        return [HelperTools sha512HmacForKey:key andData:data];
    NSAssert(NO, @"Unexpected error: unsupported HT hash method!", (@{@"method": nilWrapper(_method)}));
    return nil;
}

@end
