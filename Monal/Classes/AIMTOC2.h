//
//  xmpp.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/18/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "protocol.h"

//constants


@interface AIMTOC2 : protocol  <UIAlertViewDelegate>{
	
	NSString* authHost ;
	 int authPort;

    NSInputStream *iStream;
    NSOutputStream *oStream;
	
	NSString* messageUser; 
	
	
	NSMutableString* messageBuffer;
	


	//response data
	NSString* responseUser; 
	
	//error messages

	BOOL  errorState; 
	
	int parserCol;
	NSMutableData* theset;


	BOOL fatal; 
	int loginstate;
	
	NSString* lastEndedElement; 
	
	int listenThreadCounter; 
	
	
	// server attributes
	BOOL SASLSupported; 
	BOOL SASLPlain; 
	BOOL SASLCRAM_MD5; 
	BOOL SASLDIGEST_MD5;
	
	BOOL ClearSupported; 
	
	NSString* sessionkey;
	int frames; 
	

	uint8_t  SFLAP_SIGNON ;
	uint8_t  SFLAP_DATA ;
	uint8_t  SFLAP_KEEP_ALIVE ;
	unsigned int MAX_LENGTH ;
	
	
short mySequenceNo; 
	
}


-(id)init2:(NSString*) theaccount:(DataLayer*) thedb;
-(bool) connect;
-(void) disconnect;

-(NSMutableData*) readData;


-(bool) login;

-(NSInteger) getBuddies;
-(bool) message:(NSString*) to:(NSString*) content;


//presence functions
-(NSInteger) setStatus:(NSString*) status;
-(NSInteger) setAway;
-(NSInteger) setAvailable;
-(NSInteger) setInvisible; 

//buddy list management commands
-(bool) removeBuddy:(NSString*) buddy; 
-(bool) addBuddy:(NSString*) buddy; 
-(void) getVcard:(NSString*) buddy;

-(bool) sendLast:(NSString*) to:(NSString*) userid;
-(bool) sendVersion:(NSString*) to:(NSString*) userid;

-(bool)sendAuthorized:(NSString*) buddy; 
-(bool)sendDenied:(NSString*) buddy; 

-(bool) talk: (NSData*) thecommand;
-(bool) sflapTalk:  (uint8_t ) type : (id) thecommand; // could be string or data depending on the type

- (void)PostSasl:(id)sender;

// variable interface
-(NSString*) getAccount; 
-(NSString*) getServer; 
-(NSString*) getResource; 

-(NSMutableArray*) getBuddyListArray;
-(NSMutableArray*) getBuddyListAdded; 
-(NSMutableArray*) getBuddyListRemoved; 
-(NSMutableArray*) getBuddyListUpdated; 

-(NSArray*) getRoster;

-(NSMutableArray*) getMessagesIn;
-(void) readMessages; 

-(void) buddyListUpdateRead;

-(BOOL) isInRemove:(NSString*) name;
-(BOOL) isInAdd:(NSString*) name;

//threads
-(void) listener;
-(bool) keepAlive;

//stream delegate
- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode;


-(NSString*) roast:(NSString*) pass; 
-(NSString*) coded:(NSString*)user:(NSString*) thepass;


@property (nonatomic, readonly) NSMutableData* theset;

struct toc_data {
		        int toc_fd;
		        char toc_ip[20];
		        int seqno;
		        int state;
	};
	
	struct sflap_hdr {
		        uint8_t  ast;
		        uint8_t  type;
		        unsigned short seqno;
		        unsigned short length;
	};
	
	struct signon {
		unsigned int ver;
			unsigned short tag;
			unsigned short length;
			char username[80];
		       
	};

@end
