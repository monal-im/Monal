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


@property (nonatomic,strong)  NSString* user;
@property (nonatomic,strong)  NSString* from;
@property (nonatomic,strong)  NSString* to;
@property (nonatomic,strong) NSString* idval;
@property (nonatomic,strong) NSString* resource;

@property (nonatomic,strong) NSString* type;

@property (nonatomic,strong) NSString* show;
@property (nonatomic,strong) NSString* status;
@property (nonatomic,strong) NSString* photo;

@property (nonatomic,strong) NSString* ver;


@end
