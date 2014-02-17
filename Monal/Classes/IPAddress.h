//
//  IPAddress.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/17/14.
//
//

#import <Foundation/Foundation.h>

@interface IPAddress : NSObject
- (NSString *)getIPAddress:(BOOL)preferIPv4;
- (NSDictionary *)getIPAddresses;
@end
