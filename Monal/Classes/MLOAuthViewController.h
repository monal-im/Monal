//
//  MLOAuthViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 1/16/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

@import UIKit;
@import WebKit;


@interface MLOAuthViewController : UIViewController <UIWebViewDelegate>

@property (nonatomic, weak) IBOutlet UIWebView *webView;
@property (nonatomic, strong)  NSURL *oAuthURL;
@property (nonatomic, copy)  void (^completionHandler)(NSString *token);


@end
