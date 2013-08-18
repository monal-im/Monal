//
//  MLIconManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import <Foundation/Foundation.h>


@interface MLIconManager : NSObject

/**
 Takes the string from the xmpp icon vcard info and stores it in an appropropriate place. 
 */
+(void) setIconForContact:(NSString*) contact andAccount:(NSString*) accountNo WithData:(NSString*) data ;

/**
 retrieves a uiimage for the icon. returns noicon.png if nothing is found. never returns nil. 
 */
+(UIImage*) getIconForContact:(NSString*) contact andAccount:(NSString*) accountNo;

@end
