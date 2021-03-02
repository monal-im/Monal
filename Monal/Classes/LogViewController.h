//
//  LogViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/20/13.
//
//

#import <UIKit/UIKit.h>

@interface LogViewController : UIViewController<UITextFieldDelegate>

@property  (nonatomic,weak) IBOutlet UITextView *logView;

@end
