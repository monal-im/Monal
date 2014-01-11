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

#pragma mark disco
/**
 makes a disco info response
 */
-(void) setDiscoInfoWithFeatures;

/**
 sets up a disco info query node
 */
-(void) setDiscoInfoNode;

/**
 sets up a disco info query node
 */
-(void) setDiscoItemNode;

#pragma mark roster
/**
gets vcard info 
 */
-(void) getVcardTo:(NSString*) to;

/**
removes a contact from the roster
 */
-(void) setRemoveFromRoster:(NSString*) jid;

/**
 Requests a full roster from the server
 */
-(void) setRosterRequest;

#pragma mark MUC
/**
 create instant room
 */
-(void) setInstantRoom;

#pragma mark Jingle

-(void) setJingleInitiateTo:(NSString*) jid andResource:(NSString*) resource;
-(void) setJingleDeclineTo:(NSString*) jid andResource:(NSString*) resource;
-(void) setJingleTerminateTo:(NSString*) jid andResource:(NSString*) resource;



@end
