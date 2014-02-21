//
//  MLImageManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import <Foundation/Foundation.h>


@interface MLImageManager : NSObject

/**
 chatview inbound background image
 */
@property (nonatomic, strong) UIImage* inboundImage;
/**
 chatview outbound background image
 */
@property (nonatomic, strong) UIImage* outboundImage;
@property (nonatomic, strong) NSString* something; 

+ (MLImageManager* )sharedInstance;


/**
 Takes the string from the xmpp icon vcard info and stores it in an appropropriate place. 
 */
-(void) setIconForContact:(NSString*) contact andAccount:(NSString*) accountNo WithData:(NSString*) data ;

/**
 retrieves a uiimage for the icon. returns noicon.png if nothing is found. never returns nil. 
 */
-(UIImage*) getIconForContact:(NSString*) contact andAccount:(NSString*) accountNo;

/**
 Purge cache in the event of  a memory warning
 */
-(void) purgeCache;
@end
