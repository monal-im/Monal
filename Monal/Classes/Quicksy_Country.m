//
//  Quicksy_Country.m
//  Monal
//
//  Created by Thilo Molitor on 28.08.24.
//  Copyright © 2024 Monal.im. All rights reserved.
//

#import "Quicksy_Country.h"
#import "MLConstants.h"

@interface Quicksy_Country()
    @property (nonatomic, strong) NSString* _Nullable name;      //has to be optional because we don't want to have NSLocalizedString() if we know the alpha-2 code
    @property (nonatomic, strong) NSString* _Nullable alpha2;    //has to be optional because the alpha-2 mapping can fail
    @property (nonatomic, strong) NSString* code;
    @property (nonatomic, strong) NSString* pattern;
@end

@implementation Quicksy_Country

-(instancetype) initWithName:(NSString* _Nullable) name alpha2:(NSString* _Nullable) alpha2 code:(NSString*) code pattern:(NSString*) pattern;
{
    self = [super init];
    self.name = name;
    self.alpha2 = alpha2;
    self.code = code;
    self.pattern = pattern;
    return self;
}

-(NSString*) id
{
    return [NSString stringWithFormat:@"%@|%@", nilDefault(self.name, @""), nilDefault(self.alpha2, @"")];
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeObject:self.alpha2 forKey:@"alpha2"];
    [coder encodeObject:self.code forKey:@"code"];
    [coder encodeObject:self.pattern forKey:@"pattern"];
}

-(instancetype) initWithCoder:(NSCoder*) coder
{
    self = [self init];
    self.name = [coder decodeObjectForKey:@"name"];
    self.alpha2 = [coder decodeObjectForKey:@"alpha2"];
    self.code = [coder decodeObjectForKey:@"code"];
    self.pattern = [coder decodeObjectForKey:@"pattern"];
    return self;
}

@end
