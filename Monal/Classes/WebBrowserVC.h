//
//  WebBrowserVC.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface WebBrowserVC : UIViewController <UIWebViewDelegate,UITextFieldDelegate>{
	IBOutlet UITextField* url;
	IBOutlet UIWebView* web; 
	IBOutlet  UIActivityIndicatorView* spinner;
	IBOutlet UIButton* stopRef; 
}
-(IBAction) goBack;
-(IBAction) goForward;
-(IBAction) stopRefresh;

@end
