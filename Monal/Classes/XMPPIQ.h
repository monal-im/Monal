//
//  XMPPIQ.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "XMLNode.h"

#define kiqGetType @"get"
#define kiqSetType @"set"
#define kiqResultType @"result"
#define kiqErrorType @"error"

@interface XMPPIQ : XMLNode

-(id) initWithId:(NSString*) sessionid andType:(NSString*) iqType;


/**
 Makes an iq to bind with a resouce. Passing nil will set no resource.
 */
-(void) setBindWithResource:(NSString*) resource;

/**
 set to attribute
 */
-(void) setiqTo:(NSString*) to;

/**
 makes iq of ping type
 */
-(void) setPing;

/**
 makes a disco info response
 */
-(void) setDiscoInfo;

/**
gets vcard info 
 */
-(void) getVcardTo:(NSString*) to;

@end
