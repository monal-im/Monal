//
//  SlidingMessageViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/22/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//



#import <Foundation/Foundation.h>

#import <UIKit/UIKit.h>
#import "tools.h"




@interface SlidingMessageViewController : UIViewController
{
	UILabel   *titleLabel;              
	UILabel   *msgLabel;
	UIImageView   *icon;
    UIButton* tapHandler;
    NSString* username;
	int x; 
	int y; 
	int width; 
	int height; 
	bool top; 
	float rotate;
}

-(void) releaser; 
-(id) correctSliderWithTitle:(NSString *)title message:(NSString *)msg userfilename:(NSString*)userfilename user:(NSString*) user;
-(id) commonInit:(NSString *)title message:(NSString *)msg userfilename:(NSString*)userfilename;
- (id)initWithTitle:(NSString *)title message:(NSString *)msg userfilename:(NSString*)userfilename;
- (id)initTopWithTitle:(NSString *)title message:(NSString *)msg userfilename:(NSString*)userfilename;
- (void)showMsg;
- (void)hideMsg;

@end