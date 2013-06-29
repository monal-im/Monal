//
//  MLXMPPManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import "MLXMPPManager.h"
#import "DataLayer.h"

@implementation MLXMPPManager


+ (MLXMPPManager* )sharedInstance
{
    static dispatch_once_t once;
    static MLXMPPManager* sharedInstance; 
    dispatch_once(&once, ^{
        sharedInstance = [[MLXMPPManager alloc] init] ;
       
    });
    return sharedInstance;
}

-(void)connectIfNecessary
{
    _accountList=[[DataLayer sharedInstance] accountList];
    for (NSArray* account in _accountList)
    {
        
    }
}


@end

