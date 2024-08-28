//
//  Quicksy_Country.h
//  Monal
//
//  Created by Thilo Molitor on 28.08.24.
//  Copyright © 2024 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Quicksy_Country : NSObject <NSSecureCoding>
    @property (readonly) NSString* id;                  //for Identifiable protocol
    @property (readonly) NSString* _Nullable name;      //has to be optional because we don't want to have NSLocalizedString() if we know the alpha-2 code
    @property (readonly) NSString* _Nullable alpha2;    //has to be optional because the alpha-2 mapping can fail
    @property (readonly) NSString* code;
    @property (readonly) NSString* pattern;
    
    -(instancetype) initWithName:(NSString* _Nullable) name alpha2:(NSString* _Nullable) alpha2 code:(NSString*) code pattern:(NSString*) pattern;
    +(BOOL) supportsSecureCoding;
@end

NS_ASSUME_NONNULL_END
