//
//  MLContact.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLContact.h"

@implementation MLContact

-(NSString *) contactDisplayName
{
    if(self.nickName) return self.nickName;
    if (self.fullName) return self.fullName;
    
    return self.contactJid;
}

@end
