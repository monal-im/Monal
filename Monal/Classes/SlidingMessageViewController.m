//
//  SlidingMessageViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/22/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "SlidingMessageViewController.h"
#import "MLImageManager.h"

#import "DDLog.h"

static const int ddLogLevel = LOG_LEVEL_ERROR;


/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 * Private interface definitions
 *~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/
@interface SlidingMessageViewController(private)
- (void)hideMsg;
@end

@implementation SlidingMessageViewController




-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}
/**************************************************************************
 *
 * Private implementation section
 *
 **************************************************************************/

#pragma mark -
#pragma mark Private Methods

/*-------------------------------------------------------------
 *
 *------------------------------------------------------------*/
- (void)hideMsg
{
	DDLogVerbose(@"hiding message"); 
	// Slide the view down off screen
	CGRect frame = self.view.frame;
	
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:.75];
	
    UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];
	
	if(top==false)
	{
	if(orientation==UIInterfaceOrientationPortraitUpsideDown)
	{
		frame.origin.y =y-44;
	}
		else
	if(orientation==UIInterfaceOrientationLandscapeLeft) 
	{
		frame.origin.x =x;
	}
		else
			if(orientation==UIInterfaceOrientationLandscapeRight) 
			{
			frame.origin.x = x;
			}
			else
			{
			frame.origin.y = y-height;
			}
	}
	else
	{
		if(orientation==UIInterfaceOrientationPortraitUpsideDown)
		{
			frame.origin.y =y;
		}
		else
			if(orientation==UIInterfaceOrientationLandscapeLeft) 
			{
				frame.origin.x =x;
			}
			else
				if(orientation==UIInterfaceOrientationLandscapeRight) 
				{
					frame.origin.x = x;
				}
				else
				{
					frame.origin.y = y-height;
				}
		
	}
	
	self.view.frame = frame;
	
 
	// To autorelease the Msg, define stop selector
	[UIView setAnimationDelegate:self];
   
	[UIView setAnimationDidStopSelector:@selector(releaser)]; 
	
	[UIView commitAnimations];
}

-(void) releaser
{
	// Release
    //[self release]; 
    if ([self.view superview])
		[self.view removeFromSuperview];
    
    DDLogVerbose(@"removed  slider"); 
	
}
 

/**************************************************************************
 *
 * Class implementation section
 *
 **************************************************************************/

#pragma mark -
#pragma mark Initialization

/*-------------------------------------------------------------
 *
 *------------------------------------------------------------*/

-(id) correctSliderWithTitle:(NSString *)title message:(NSString *)msg user:(NSString*)user account:(NSString*) account_id
{
    username=user;
	//Note: this assumes its in chatwin
	UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];
	if (([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)&& (! ((orientation==UIInterfaceOrientationPortraitUpsideDown)
											 || (orientation==UIInterfaceOrientationPortrait) )))
	{
		[self initWithTitle:title message:msg  user:user account:account_id];
		
	}
	else
	{
	
        [self initTopWithTitle:title message:msg user:user account:account_id];
		
	}
	
	return self; 
	
}

-(void) commonInit:(NSString *)title message:(NSString *)msg user:(NSString*)user account:(NSString*) account_id
{
	// Notice the view y coordinate is offscreen (480)
	// This hides the view
	self.view = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];
	[self.view setBackgroundColor:[UIColor blackColor]];
	[self.view setAlpha:.87];
	
	//icon
	icon =[[UIImageView alloc] initWithFrame:CGRectMake(5, 5, 32, 32)] ;
    icon.image=[[MLImageManager sharedInstance] getIconForContact:user andAccount:account_id];
    [self.view addSubview:icon];
    
	// Title
	titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 5, 280, 30)] ;
	titleLabel.font = [UIFont boldSystemFontOfSize:17];
	titleLabel.text = title;
	titleLabel.textAlignment = UITextAlignmentCenter;
	titleLabel.textColor = [UIColor whiteColor];
	titleLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:titleLabel];
	
	// Message
	msgLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 5, 280, 80)];
	msgLabel.font = [UIFont systemFontOfSize:15];
	msgLabel.text = msg;
	msgLabel.textAlignment = UITextAlignmentCenter;
	msgLabel.textColor = [UIColor whiteColor];
	msgLabel.backgroundColor = [UIColor clearColor];
	
	if(rotate!=0)
	{
		CGAffineTransform transform = [self.view  transform];
		transform = CGAffineTransformRotate(transform, rotate);
		self.view.transform=transform;
	}
	
	[self.view addSubview:msgLabel];
}

- (id)initTopWithTitle:(NSString *)title message:(NSString *)msg user:(NSString*) user account:(NSString*) account_id
{
	top=true; 
	if (self = [super init]) 
	{
	
		UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];
		
		rotate=0;
		
		if(orientation==UIInterfaceOrientationPortraitUpsideDown)
		{ rotate=[tools degreesToRadians:(float)180]; 
			
			
				x=0; 
				y=480; 
				width=320; 
				height=90; 
			
			
			
		}
		
		if(orientation==UIInterfaceOrientationPortrait) 
			
		{
			
				x=0; 
				
				width=320; 
				height=90; 
				y=0-height;
		}
		
		if(orientation==UIInterfaceOrientationLandscapeLeft) 
		{
			
			rotate= [tools degreesToRadians:-90]; 
            width=320;
            height=90;
			y=150;
			x=0-height-25;
		}
		
		if(orientation==UIInterfaceOrientationLandscapeRight) 
		{
			rotate= [tools degreesToRadians:90]; 
			width=320;
			height=90;
			x=300;
			y=480-220;
		}
		
		[self commonInit:title message:msg user:user account:account_id];
	}
	
	return self;
}

- (id)initWithTitle:(NSString *)title message:(NSString *)msg user:(NSString*) user account:(NSString*) account_id
{
	top=false; 
	if (self = [super init]) 
	{
        UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];
		
		 rotate=0; 
		
		if(orientation==UIInterfaceOrientationPortraitUpsideDown)
		{ rotate=[tools degreesToRadians:(float)180]; 
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
			{
				
				y=0-height-44;
				width=320; 
				height=100; 
				x=768-width; 
				
			}
			else
			{
				x=0; 
				
				width=320; 
				height=90; 
				y=0-height+59; 
			}
		}
		
		if(orientation==UIInterfaceOrientationPortrait) 
		   
		{
			if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
			{
				x=0; 
				y=1020;
				width=324; 
				height=100; 
			}
			else
			{
				x=0; 
				y=480-4; 
				width=320; 
				height=90; 
			}
				
				
		}
	
		if(orientation==UIInterfaceOrientationLandscapeLeft) 
		{
			
			rotate= [tools degreesToRadians:-90]; 
		 if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
			{
				
				width=324; 
				
				height=100+44; 
				x=768; 
				y=1024-234;
			}
			else
			{
				
				width=320; 
				 
				height=90+44; 
				x=320; 
				y=480-220;
				
			}
		}
		
		if(orientation==UIInterfaceOrientationLandscapeRight) 
		{
			rotate= [tools degreesToRadians:90]; 
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
			{
				

				width=324; 
				height=100+44+44; 
				x=0-height-44; 
				
				y=64;
			}
			else
			{
				width=320; 
				height=90+44+44; 
				
				y=25; 
				
				x=0-height-44; 
        
		}
		
		[self commonInit:title message:msg user:user account:account_id];
	}
	
	return self;
}
}

#pragma mark -
#pragma mark Message Handling

/*-------------------------------------------------------------
 *
 *------------------------------------------------------------*/

- (void)showMsg
{
	//  UIView *view = self.view;
    CGRect frame = self.view.frame;

	
	// landscape of  portrait?

	UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];

	if(top==false)
	{
	
	if(orientation==UIInterfaceOrientationPortraitUpsideDown)
	{
		frame.origin.y = y+height-30;
	}
	
	 if 
		(orientation==UIInterfaceOrientationPortrait)
	 {
	 
	// portrait
		frame.origin.y = y+height;
	 
	 
	 }
	
	if(orientation==UIInterfaceOrientationLandscapeLeft) 		
	 {
	 
	 
		  if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
		 {
			 frame.origin.x = x-height;
			 
		 }
		 else frame.origin.x = x-height;
	 
	 }
	
	if(orientation==UIInterfaceOrientationLandscapeRight)
	{
		 if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
		{
			frame.origin.x = x+height;
			
		}
		else frame.origin.x = x+height;
	}
	}
	else
	{
		if(orientation==UIInterfaceOrientationPortraitUpsideDown)
		{
			frame.origin.y = y-height-30;
		}
		
		if 
			(orientation==UIInterfaceOrientationPortrait)
		{
			
			// portrait
			frame.origin.y = y+height;

		}
		
		if(orientation==UIInterfaceOrientationLandscapeLeft) 		
		{
			
			//top never called for ipad
			 frame.origin.x = x+height+64;
			
		}
		
		if(orientation==UIInterfaceOrientationLandscapeRight)
		{
			//top never called for ipad
			 frame.origin.x = x-height;
		}
	}
	
	// Slide up based on y axis
	// A better solution over a hard-coded value would be to
	// determine the size of the title and msg labels and 
	// set this value accordingly
	
    tapHandler = [UIButton buttonWithType:UIButtonTypeCustom];
    tapHandler.frame=frame; 
    [tapHandler addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:tapHandler]; 
    
	
	
	[UIView animateWithDuration:.75f animations:^{
       self.view.frame = frame;
    }];
	
	
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_current_queue(),
                   ^{
                       [self hideMsg];
    });
	
}

-(void) tapped
{
    DDLogVerbose(@"tapped popup");
    // show the user 
    NSArray* vals= [[NSArray alloc] initWithObjects:username, nil]; 
    NSArray* keys= [[NSArray alloc] initWithObjects:@"username", nil]; 
    NSDictionary* dic =  [[NSDictionary alloc] initWithObjects:vals forKeys:keys];
    
    [[NSNotificationCenter defaultCenter] 
	 postNotificationName: @"showSignal" object:nil userInfo:dic ];
   
    
}

#pragma mark -
#pragma mark Cleanup



/*-------------------------------------------------------------
 *
 *------------------------------------------------------------*/

@end