//
//  MLImageManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import <Foundation/Foundation.h>


@interface MLImageManager : NSObject



#if TARGET_OS_IPHONE
/**
 chatview inbound background image
 */
@property (nonatomic, strong) UIImage* inboundImage;
/**
 chatview outbound background image
 */
@property (nonatomic, strong) UIImage* outboundImage;

#else

#endif


+ (MLImageManager* )sharedInstance;


/**
 Takes the string from the xmpp icon vcard info and stores it in an appropropriate place. 
 */
-(void) setIconForContact:(NSString*) contact andAccount:(NSString*) accountNo WithData:(NSString*) data ;


#if TARGET_OS_IPHONE
/**
 retrieves a uiimage for the icon. returns noicon.png if nothing is found. never returns nil.
 */
-(UIImage *) getIconForContact:(NSString*) contact andAccount:(NSString *) accountNo;

#else
/**
 retrieves a uiimage for the icon. returns noicon.png if nothing is found. never returns nil.
 */
-(NSImage *) getIconForContact:(NSString*) contact andAccount:(NSString *) accountNo;

#endif

/**
 Purge cache in the event of  a memory warning
 */
-(void) purgeCache;
@end
