//
//  iq.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/12/12.
//
//

#import <Foundation/Foundation.h>

@interface iq : NSObject
{
    
}

-(void) reset;

@property (nonatomic)  NSString* user;
@property (nonatomic)  NSString* from;
@property (nonatomic)  NSString* to;
@property (nonatomic) NSString* idval;
@property (nonatomic) NSString* resource;

@property (nonatomic) NSString* type;
@end
