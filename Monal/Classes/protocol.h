//
//  protocol.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/18/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

/*
 This is the protocl base class that all other protocols will implement, maintaining a standard interface 
 for communication with the UI
 */

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "DataLayer.h"
#import "tools.h"
#import "PasswordManager.h"

#include <CommonCrypto/CommonDigest.h>


@interface protocol : NSObject  <UIAlertViewDelegate, NSStreamDelegate>{
	
	unsigned short port; 
	NSString* server; 
	BOOL SSL; 
	NSString*  account; 

	NSString* resource; 
	
	NSString* domain; 

   
	
	
	NSString* sessionid; 
	NSString* State;
	NSString* presenceUser; 
	NSString* presenceUserid; 
	NSString* presenceUserFull; 
	
	NSString* presenceShow; 
	NSString* presenceStatus; 
	NSString* presencePhoto; 
	NSString* presenceType; 
	
	
	NSString* vCardPhotoBinval; 
	NSString* vCardPhotoType; 
	NSString* vCardFullName;
	NSString* vCardUser; 
	BOOL vCardDone; 
	
	int streamOpen; 

	BOOL away; 
	NSString* statusMessage;

	//NSMutableArray* buddyListAdded;
	//NSMutableArray* buddyListRemoved;
	//NSMutableArray* buddyListUpdated;
	//NSMutableArray* messagesIn;
	
	//NSMutableArray* buddyListKeys; 
	
	//NSMutableArray* buddiesOnline; // those who are online only
	//NSMutableArray* roster; // this is the full list of everyone
	

		
		DataLayer* db;
		BOOL loggedin; 
		bool listenerthread; 
	
		NSString* accountNumber;
	
	bool streamError;
	bool messagesFlag;
	bool presenceFlag;
	
}

-(id)init:(NSString*) theserver:(unsigned short) theport:(NSString*) theaccount: (NSString*) theresource:(NSString*) thedomain: (BOOL) SSLsetting : (DataLayer*) thedb:(NSString*) accontNo;
-(bool) connect;
-(void) disconnect;

-(NSMutableData*) readData;


-(bool) login:(id)sender;

-(NSInteger) getBuddies;
-(bool) message:(NSString*) to:(NSString*) content:(BOOL) group;

#pragma mark Muc
-(void) joinMuc:(NSString*) to :(NSString*) password;
-(bool) closeMuc:(NSString*) buddy; 


#pragma mark presence functions
-(NSInteger) setStatus:(NSString*) status;
-(NSInteger) setAway;
-(NSInteger) setAvailable;
-(NSInteger) setInvisible; 

#pragma mark buddy list management commands
-(bool) removeBuddy:(NSString*) buddy; 
-(bool) addBuddy:(NSString*) buddy; 
-(void) getVcard:(NSString*) buddy;

-(bool)sendAuthorized:(NSString*) buddy; 
-(bool)sendDenied:(NSString*) buddy; 

-(bool) talk: (NSString*) xmpprequest;



// variable interface
-(NSString*) getAccount; 
-(NSString*) getServer; 
-(NSString*) getResource; 

-(NSArray*) getBuddyListArray;
-(NSArray*) getBuddyListAdded; 
-(NSArray*) getBuddyListRemoved; 
-(NSArray*) getBuddyListUpdated; 

-(NSArray*) getRoster;

-(NSArray*) getMessagesIn;


-(void) setPriority:(int) val; 

//-(void) readMessages; 

-(void) buddyListUpdateRead;

-(BOOL) isInRemove:(NSString*) name;
-(BOOL) isInAdd:(NSString*) name;

//threads
-(void) listener;
-(bool) keepAlive;



- (NSString *)base64Encoding:(NSString*) string;
- (NSData*)dataWithBase64EncodedString:(NSString *)string;
- (NSString *) MD5:(NSString*)string ;
- (NSString *) MD5_16:(NSString*)string ;

@property (nonatomic, readonly) bool streamError;


@property (nonatomic, readonly)  BOOL loggedin;
@property (nonatomic, readonly)  NSString* accountNumber;
@property (nonatomic, readonly)  NSString* account;
@property (nonatomic, readonly)  NSString* domain;

@property (nonatomic )  bool messagesFlag; 
@property (nonatomic) bool presenceFlag; 

@property (nonatomic, retain) NSString* statusMessage;

@end
