//
//  chatViewController.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DataLayer.h"
#import "HPGrowingTextView.h"
#import "MLConstants.h"
#import "MLXMPPManager.h"
#import "MLNotificationManager.h"


@interface chatViewController : UIViewController <HPGrowingTextViewDelegate,UITableViewDelegate, UITableViewDataSource>
{

    UIView *containerView;
    HPGrowingTextView *chatInput;
	CGRect oldFrame;
	NSString* _contactFullName;
    
	bool firstmsg;
	bool groupchat;
	
	bool wasaway; 
	bool wasoffline; 
	bool msgthread;
//    UIPageControl* pages;
    
    NSArray* activeChats;
    NSMutableArray* _messagelist;
 
    UITableView* _messageTable;
    NSDictionary* _contact; 
}

@property (nonatomic,strong)  NSString* contactName;


-(id) initWithContact:(NSDictionary*) contact  ;

/**
 Receives the new message notice and will update if it is this user. 
 */
-(void) handleNewMessage:(NSNotification *)notification;
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message;

#pragma mark gesture stuff

-(void) showSignal:(NSNotification*) note; 
-(void)swipeDetected:(UISwipeGestureRecognizer *)recognizer;


-(void) handleInput:(NSString *)text;
//notification 
-(void) keyboardWillShow:(NSNotification *) note;
-(void) keyboardWillHide:(NSNotification *) note;


//content generation 
//-(NSString*) makeMessageHTMLfrom:(NSString*) from withMessage:(NSString*) themessage andTime:(NSString*) time isLive:(BOOL) liveChat;
//-(NSString*) emoticonsHTML:(NSString*) message; 

/**
 full own username with domain e.g. aa@gmail.com
 */
@property (nonatomic, strong) NSString* jid;

/**
 This is the account number of the account this user is for
 */
@property (nonatomic, strong) NSString* accountNo;

@end
