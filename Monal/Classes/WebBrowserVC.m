
//
//  WebBrowserVC.m
//  Monal
//
//  Created by Anurodh Pokharel on 9/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "WebBrowserVC.h"


@implementation WebBrowserVC

- (void)viewDidDisappear:(BOOL)animated
{
	debug_NSLog(@"web view did hide"); 
	[web stopLoading];
}

-(IBAction) goBack
{
	[web goBack];
}

-(IBAction) goForward
{
	[web goForward];
}

-(IBAction) stopRefresh;
{
	if(web.loading)
	   {
		   [web stopLoading]; 
		   [stopRef setImage:[UIImage imageNamed:@"reload.png"] forState: UIControlStateNormal ];
	   }
	   else
	   {
		   [web reload];
		      [stopRef setImage:[UIImage imageNamed:@"stop.png"] forState: UIControlStateNormal ];
	   }
}

-(void)viewDidAppear:(BOOL)animated 
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
    if([self.title isEqualToString:@"Help"])
    {
        //if something hadnt been loaded yet. 
        if([url.text isEqualToString:@""])
        {
        
    NSURLRequest* request= [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://monal.im/topics/help/"]];
	[web loadRequest:request]; 
        }
	}
    
    [pool release];
}

#pragma mark textfield delegate
- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString* thetext=[textField text]; 
	if([thetext length]>=4) 
	{
	if(!([thetext hasPrefix:@"http://"]))
	{
		thetext=[NSString stringWithFormat:@"http://%@", thetext];		
		[textField setText:thetext];
	}
	
	//[url resignFirstResponder];
	NSURLRequest* request= [NSURLRequest requestWithURL:[NSURL URLWithString:thetext]];
	[web loadRequest:request]; 
		
	}
	[pool release];
	return true; 
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	[textField resignFirstResponder];
	return true; 
}

#pragma mark webview delegate
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
	//update the text field
	[url setText:[[request mainDocumentURL] absoluteString]];
	return true;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	[spinner stopAnimating];
	 [stopRef setImage:[UIImage imageNamed:@"reload.png"] forState: UIControlStateNormal ];
	
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
	[spinner startAnimating];
	 [stopRef setImage:[UIImage imageNamed:@"stop.png"] forState: UIControlStateNormal ];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
	[spinner stopAnimating];
	 [stopRef setImage:[UIImage imageNamed:@"reload.png"] forState: UIControlStateNormal ];
	
/*	UIAlertView *addError = [[UIAlertView alloc] 
							  initWithTitle:@"Web Page Error" 
							  message:@"Could not load web page. "
							  delegate:self cancelButtonTitle:@"Close"
							  otherButtonTitles: nil] ;
	[addError show];
	[addError release];*/
}



- (void)dealloc {
    [super dealloc];
}


@end
