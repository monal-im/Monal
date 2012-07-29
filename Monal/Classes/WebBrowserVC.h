//
//  WebBrowserVC.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MBProgressHud.h"


@interface WebBrowserVC : UIViewController <UIWebViewDelegate,UITextFieldDelegate,MBProgressHUDDelegate>{
	IBOutlet UITextField* url;
	IBOutlet UIWebView* web; 
	IBOutlet  UIActivityIndicatorView* spinner;
	IBOutlet UIButton* stopRef;
    
    MBProgressHUD* HUD ;
}
-(IBAction) goBack;
-(IBAction) goForward;
-(IBAction) stopRefresh;

@end
