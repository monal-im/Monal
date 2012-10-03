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

@property (nonatomic,strong)  NSString* user;
@property (nonatomic,strong)  NSString* from;
@property (nonatomic,strong)  NSString* to;
@property (nonatomic,strong) NSString* idval;
@property (nonatomic,strong) NSString* resource;

@property (nonatomic,strong) NSString* type;

//not in an iq stanza but useful to ahve in the object
@property (nonatomic,strong) NSString* ver;
@end
