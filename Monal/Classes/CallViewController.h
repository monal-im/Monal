//
//  CallViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/22/13.
//
//

#import <UIKit/UIKit.h>
#import "MLContact.h"

@interface CallViewController : UIViewController

@property (nonatomic, strong)  MLContact* contact;

/**
Icon of the person being called
 */
@property (nonatomic, weak) IBOutlet UIImageView* userImage;

/**
 The name of the person being called.
 */
@property (nonatomic, weak) IBOutlet UILabel* userName;

/**
 cancels the call and dismisses window
 */
-(IBAction)cancelCall:(id)sender;

@end
