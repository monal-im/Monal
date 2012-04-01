//
//  userSearch.h
//  Monal
//
//  Created by Anurodh Pokharel on 3/27/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//
//XEP-0055: Jabber Search , basic user search, doesnt suppport x:data

#import <Foundation/Foundation.h>


@interface iqSearch : NSObject {
    NSMutableArray* userFields; 
    
}

-(id) init; 
-(NSString*) constructUserSearch:(NSString*) to :(NSString*) request;

@property (nonatomic) NSMutableArray* userFields; 

@end
