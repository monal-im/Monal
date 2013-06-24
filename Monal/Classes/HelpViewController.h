//
//  HelpViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>

#define kMonalHelpURL @"http://monal.im/help"

@interface HelpViewController : UIViewController <UIWebViewDelegate>

@property (nonatomic, strong) UIWebView* webView;

-(void) goBack;

@end
