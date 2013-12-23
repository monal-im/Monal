//
//  CallViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/22/13.
//
//

#import <UIKit/UIKit.h>

@interface CallViewController : UIViewController
{
    NSDictionary* _contact;
}

/**
Icon of the person being called
 */
@property (nonatomic, weak) IBOutlet UIImageView* userImage;

/**
 The name of the person being called.
 */
@property (nonatomic, weak) IBOutlet UILabel* userName;


/**
 Initlizes call with contact from account
 */
-(id) initWithContact:(NSDictionary*) contact;

/**
 cancels the call and dismisses window
 */
-(IBAction)cancelCall:(id)sender;

@end
