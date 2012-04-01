//
//  SlidingMessageViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/22/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "SlidingMessageViewController.h"


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
	debug_NSLog(@"hiding message"); 
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
			frame.origin.y = y;
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
					frame.origin.y = y;
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
    
    debug_NSLog(@"removed  slider"); 
	
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

-(id) correctSlider:(NSString *)title :(NSString *)msg:(NSString*)userfilename:(NSString*) user
{
	
    username=user; 
	//Note: this assumes its in chatwin
	
	UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];
	
	
	if(([[tools machine] hasPrefix:@"iPad"])&& (! ((orientation==UIInterfaceOrientationPortraitUpsideDown)
											 || (orientation==UIInterfaceOrientationPortrait) )))
	{
		
		[self
		 initWithTitle:title message:msg:userfilename];   
		
	}
	else
	{
	
		 [self initTopWithTitle:title message:msg:userfilename];     
		
	}
	
	return self; 
	
}

-(id) commonInit:(NSString *)title :(NSString *)msg:(NSString*)userfilename
{
	// Notice the view y coordinate is offscreen (480)
	// This hides the view
	self.view = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];
	[self.view setBackgroundColor:[UIColor blackColor]];
	[self.view setAlpha:.87];
	
	//icon
	icon =[[UIImageView alloc] initWithFrame:CGRectMake(5, 5, 32, 32)] ;
	
	if(![userfilename isEqualToString:@""])
	{
		if([userfilename isEqualToString:@"noicon"])
			icon.image=[UIImage imageNamed:@"noicon.png"];
		else
			icon.image=[UIImage imageWithContentsOfFile:userfilename];
		
		[self.view addSubview:icon];
	}
	
   
    
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
	return nil; 
}

- (id)initTopWithTitle:(NSString *)title message:(NSString *)msg:(NSString*)userfilename
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
				y=0-height+69; 
			
			
		
			
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
		
		[self commonInit:title:msg:userfilename];
	}
	
	return self;
}

- (id)initWithTitle:(NSString *)title message:(NSString *)msg:(NSString*)userfilename
{
	top=false; 
	if (self = [super init]) 
	{
		
		
		
		
		UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];
		
		 rotate=0; 
		
		if(orientation==UIInterfaceOrientationPortraitUpsideDown)
		{ rotate=[tools degreesToRadians:(float)180]; 
			if([[tools machine] hasPrefix:@"iPad"] )
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
			if([[tools machine] hasPrefix:@"iPad"] )
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
			if([[tools machine] hasPrefix:@"iPad"] )
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
			if([[tools machine] hasPrefix:@"iPad"] )
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
		}
		
		
		[self commonInit:title:msg:userfilename];
		
	}
	
	return self;
}

#pragma mark -
#pragma mark Message Handling

/*-------------------------------------------------------------
 *
 *------------------------------------------------------------*/

- (void)slideKiller:(SlidingMessageViewController*)slider
{
	
	debug_NSLog(@"sldier hide thread start"); 
	sleep(3); //wait 3 seconds and then die
	[slider hideMsg];
	; 
	debug_NSLog(@"sldier hide thread end"); 
   
    
	[NSThread exit];
}

- (void)showMsg
{
	//  UIView *view = self.view;
    
  
    
	CGRect frame = self.view.frame;
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:.75];
	
	// landscape of  portrait?

	UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];

	if(top==false)
	{
	
	if(orientation==UIInterfaceOrientationPortraitUpsideDown)
	{
		frame.origin.y = y+height-10;
	}
	
	 if 
		(orientation==UIInterfaceOrientationPortrait)
	 {
	 
	// portrait
		frame.origin.y = y-height-44;
	 
	 
	 }
	
	if(orientation==UIInterfaceOrientationLandscapeLeft) 		
	 {
	 
	 
		 if([[tools machine] hasPrefix:@"iPad"] )
		 {
			 frame.origin.x = x-height;
			 
		 }
		 else frame.origin.x = x-height;
	 
	 }
	
	if(orientation==UIInterfaceOrientationLandscapeRight)
	{
		if([[tools machine] hasPrefix:@"iPad"] )
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
			frame.origin.y = y-height-10;
		}
		
		if 
			(orientation==UIInterfaceOrientationPortrait)
		{
			
			// portrait
			frame.origin.y = y+height-44;
			
			
		}
		
		if(orientation==UIInterfaceOrientationLandscapeLeft) 		
		{
			
			//top never called for ipad
			 frame.origin.x = x+height+44;
			
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
    
	self.view.frame = frame;
	
	[UIView commitAnimations];
	
	
	[NSThread detachNewThreadSelector:@selector(slideKiller:) toTarget:self withObject:self];
	// Hide the view after the requested delay
//	[self performSelector:@selector(hideMsg) withObject:nil afterDelay:delay];
	
}

-(void) tapped
{
    debug_NSLog(@"tapped popup");
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