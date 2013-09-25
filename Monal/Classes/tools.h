//
//  tools.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/15/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface tools : NSObject {
}

+(UIImage*)  resizedImage:(UIImage *)inImage withRect: (CGRect) thumbRect;
+ (float)degreesToRadians:(float)degrees;
+ (NSString *)flattenHTML:(NSString *)html trimWhiteSpace:(BOOL)trim;

@end
