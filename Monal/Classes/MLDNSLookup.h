//
//  MLDNSLookup.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/4/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLDNSLookup : NSObject
-(NSArray*) dnsDiscoverOnDomain:(NSString*) domain;
@end

NS_ASSUME_NONNULL_END
