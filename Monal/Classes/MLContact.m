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

+(MLContact *) contactFromDictionary:(NSDictionary *) dic
{
    MLContact *contact =[[MLContact alloc] init];
    contact.contactJid=[dic objectForKey:@"buddy_name"];
    contact.nickName=[dic objectForKey:@"nick"];
    contact.fullName=[dic objectForKey:@"full_name"];
    contact.imageFile=[dic objectForKey:@"filename"];
    
    contact.accountId=[NSString stringWithFormat:@"%@", [dic objectForKey:@"account_id"]];
    
    contact.isGroup=[[dic objectForKey:@"muc"] boolValue];
    contact.groupSubject=[dic objectForKey:@"muc_subject"];
    contact.accountNickInGroup=[dic objectForKey:@"muc_nick"];
    
    contact.statusMessage=[dic objectForKey:@"status"];
    contact.state=[dic objectForKey:@"state"];
    
    contact.unreadCount=[[dic objectForKey:@"count"] integerValue];
    
    return contact;
}

+(MLContact *) contactFromDictionary:(NSDictionary *) dic withDateFormatter:(NSDateFormatter *) formatter
{
    MLContact *contact = [MLContact contactFromDictionary:dic];
    contact.lastMessageTime = [formatter dateFromString:[dic objectForKey:@"lastMessageTime"]]; 
    return contact;
}

@end
