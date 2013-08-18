//
//  MLIconManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import <Foundation/Foundation.h>
#import "DataLayer.h"

@interface MLIconManager : NSObject

+(void) setIconForContact:(NSString*) contact andAccount:(NSString*) accountNo WithData:(NSData*) data andFileName:(NSString*) fileName;
+(UIImage*) getIconForContact:(NSString*) contact andAccount:(NSString*) accountNo;

@end
