//
//  presence.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/12/12.
//
//

#import <Foundation/Foundation.h>

@interface presence : NSObject
{
   
}

-(void) reset;


@property (nonatomic)  NSString* user;
@property (nonatomic)  NSString* from;
@property (nonatomic)  NSString* to;
@property (nonatomic) NSString* idval;
@property (nonatomic) NSString* resource;

@property (nonatomic) NSString* type;

@property (nonatomic) NSString* show;
@property (nonatomic) NSString* status;
@property (nonatomic) NSString* photo;


@end
