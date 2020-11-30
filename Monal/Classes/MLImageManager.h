//
//  MLImageManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import <Foundation/Foundation.h>

@import UIKit;

@interface MLImageManager : NSObject

/**
 chatview inbound background image
 */
@property (nonatomic, strong) UIImage* _Nullable inboundImage;
/**
 chatview outbound background image
 */
@property (nonatomic, strong) UIImage* _Nullable outboundImage;

@property (nonatomic, strong) UIImage* _Nullable chatBackground;


+ (MLImageManager* _Nonnull )sharedInstance;


/**
 Takes the string from the xmpp icon vcard info and stores it in an appropropriate place. 
 */
-(void) setIconForContact:(NSString* _Nonnull) contact andAccount:(NSString* _Nonnull) accountNo WithData:(NSData* _Nullable) data ;

-(BOOL) saveBackgroundImageData:(NSData* _Nonnull) data;

/**
 retrieves a uiimage for the icon. returns noicon.png if nothing is found. never returns nil.
 */
-(void) getIconForContact:(NSString*_Nonnull) contact andAccount:(NSString *_Nonnull) accountNo withCompletion:(void (^_Nullable)(UIImage *_Nullable))completion;

-(UIImage *_Nullable) getBackground;

/**
 Purge cache in the event of  a memory warning
 */
-(void) purgeCache;

@end
