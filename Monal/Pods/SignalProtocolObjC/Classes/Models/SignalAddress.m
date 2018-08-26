//
//  SignalAddress.m
//  Pods
//
//  Created by Chris Ballinger on 6/27/16.
//
//

#import "SignalAddress.h"
#import "SignalAddress_Internal.h"

@implementation SignalAddress

- (void) dealloc {
    if (_address) {
        free(_address);
    }
}

- (instancetype) initWithName:(NSString *)name deviceId:(int32_t)deviceId {
    NSParameterAssert(name);
    if (!name) {
        return nil;
    }
    if (self = [super init]) {
        _name = [name copy];
        _deviceId = deviceId;
        _address = malloc(sizeof(signal_protocol_address));
        _address->name = [self.name UTF8String];
        _address->name_len = [self.name lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        _address->device_id = self.deviceId;
    }
    return self;
}

- (instancetype) initWithAddress:(const signal_protocol_address*)address {
    NSParameterAssert(address);
    NSParameterAssert(address->name);
    if (!address) {
        return nil;
    }
    if (!address->name) {
        return nil;
    }
    if (self = [self initWithName:[NSString stringWithUTF8String:address->name] deviceId:address->device_id]) {
    }
    return self;
}

@end
