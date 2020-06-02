//
//  MLMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLMessage.h"

@implementation MLMessage

+(MLMessage *) messageFromDictionary:(NSDictionary *) dic withDateFormatter:(NSDateFormatter *) formatter
{
    MLMessage *message = [[MLMessage alloc] init];
    message.accountId=[NSString stringWithFormat:@"%@", [dic objectForKey:@"account_id"]];
    
    message.from=[dic objectForKey:@"message_from"];
    message.actualFrom= [dic objectForKey:@"af"];
    message.messageText= [dic objectForKey:@"message"];
    message.to=[dic objectForKey:@"message_to"];
    
    message.messageId=[dic objectForKey:@"messageid"];
    message.stanzaId=[dic objectForKey:@"stanzaid"];
    message.messageDBId=[dic objectForKey:@"message_history_id"];
    message.timestamp =[formatter dateFromString:[dic objectForKey:@"thetime"]]; 
    message.messageType=[dic objectForKey:@"messageType"];
    
    message.hasBeenReceived=[(NSNumber *)[dic objectForKey:@"received"] boolValue];
    message.hasBeenSent=[(NSNumber *)[dic objectForKey:@"delivered"] boolValue];
    message.encrypted=[(NSNumber *)[dic objectForKey:@"encrypted"] boolValue];
  
    message.unread=[(NSNumber *)[dic objectForKey:@"unread"] boolValue];
    
    message.previewText=[dic objectForKey:@"previewText"];
    message.previewImage=[NSURL URLWithString:[dic objectForKey:@"previewImage"]];
    
    message.errorType=[dic objectForKey:@"errorType"];
    message.errorReason=[dic objectForKey:@"errorReason"];
    
    return message;
}

@end
