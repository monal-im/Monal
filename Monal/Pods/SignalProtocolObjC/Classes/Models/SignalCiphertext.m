//
//  SignalCiphertext.m
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import "SignalCiphertext.h"

@implementation SignalCiphertext

- (instancetype) initWithData:(NSData*)data
                         type:(SignalCiphertextType)type {
    NSParameterAssert(data);
    if (!data) { return nil; }
    if (self = [super init]) {
        _data = data;
        _type = type;
    }
    return self;
}

@end
