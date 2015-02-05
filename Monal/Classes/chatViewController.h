//
//  chatViewController.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
// 

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

#import "DataLayer.h"
#import "HPGrowingTextView.h"
#import "MLConstants.h"
#import "MLXMPPManager.h"
#import "MLNotificationManager.h"
#import "MLChatCell.h"


@interface chatViewController : UIViewController <HPGrowingTextViewDelegate,UITableViewDelegate, UITableViewDataSource>
{

    UIView *containerView;
    HPGrowingTextView *chatInput;
	CGRect oldFrame;
	NSString* _contactFullName;
    
	bool _firstmsg;
	
	bool wasaway; 
	bool wasoffline; 
//    UIPageControl* pages;
    
    NSArray* activeChats;
    NSMutableArray* _messagelist;
    NSDictionary* _contact;
    
    UITableView* _messageTable;
    
    UIView* _topBarView;
    UILabel* _topName;
    UIImageView* _topIcon;
    
    BOOL  _isMUC;
    
    NSString* _day;
    BOOL _keyboardVisible; 
}

@property (nonatomic,strong)  NSString* contactName;


-(id) initWithContact:(NSDictionary*) contact  ;

/**
 if day is specified this is a log
 */
-(id) initWithContact:(NSDictionary*) contact  andDay:(NSString* )day;

/**
 Receives the new message notice and will update if it is this user. 
 */
-(void) handleNewMessage:(NSNotification *)notification;
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message andId:(NSString *) messageId;

#pragma mark gesture stuff

//notification
-(void) keyboardWillShow:(NSNotification *) note;
-(void) keyboardWillHide:(NSNotification *) note;

-(void) retry:(id) sender;

-(void) reloadTable; 

/**
 full own username with domain e.g. aa@gmail.com
 */
@property (nonatomic, strong) NSString* jid;

/**
 This is the account number of the account this user is for
 */
@property (nonatomic, strong) NSString* accountNo;

@end
