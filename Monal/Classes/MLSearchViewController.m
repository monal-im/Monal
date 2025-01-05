//
//  MLSearchViewController.m
//  Monal
//
//  Created by jimtsai (poormusic2001@gmail.com)  on 2020/9/23.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLSearchViewController.h"
#import <monalxmpp/DataLayer.h>

@interface MLSearchViewController ()
@property (nonatomic, strong) NSMutableArray* searchResultMessageList;
@property (nonatomic, strong) NSMutableDictionary* searchResultMessageDictionary;
@property (nonatomic, strong) NSMutableDictionary* messageDictionary;
@property (nonatomic, strong) UIToolbar* toolbar;
@property (nonatomic, strong) UIBarButtonItem* searchResultIndicatorItem;
@property (nonatomic, strong) UIBarButtonItem* prevItem;
@property (nonatomic, strong) UIBarButtonItem* nextItem;
@property (nonatomic, strong) UIBarButtonItem* epmtyItem;

@property (nonatomic) unsigned int curIdxHistory;
@end

@implementation MLSearchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Do any additional setup after loading the view.
    self.searchBar.delegate = self;
    self.isLoadingHistory = NO;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    CGFloat xAxis = self.searchBar.frame.origin.x;
    CGFloat yAxis = self.searchBar.frame.origin.y;
    CGFloat height = self.searchBar.frame.size.height;
    CGFloat width = self.searchBar.frame.size.width;
    if (yAxis > 50) {
        self.searchBar.frame = CGRectMake(xAxis, yAxis-50, width, height);
    }
    
    self.toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.searchBar.frame.size.width, self.searchBar.frame.size.height)];
    UniChar upCode = 0x2191;
    UniChar downCode = 0x2193;
    NSString *upCodeString = [NSString stringWithCharacters:&upCode length:1];
    NSString *downCodeString = [NSString stringWithCharacters:&downCode length:1];
    self.prevItem = [[UIBarButtonItem alloc] initWithTitle:upCodeString style:UIBarButtonItemStylePlain target:self action:@selector(doPreviousAction)];
    self.nextItem = [[UIBarButtonItem alloc] initWithTitle:downCodeString style:UIBarButtonItemStylePlain target:self action:@selector(doNextAction)];
    self.searchResultIndicatorItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:self action:nil];
    self.epmtyItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    [self.toolbar sizeToFit];
    
    self.curIdxHistory = 0;
    
    if (!self.searchResultMessageDictionary)
        self.searchResultMessageDictionary = [NSMutableDictionary new];
    
    if (!self.messageDictionary)
        self.messageDictionary = [NSMutableDictionary new];
    
    [self.searchResultDelegate doGetMsgData];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    self.isLoadingHistory = NO;
    self.searchResultMessageList = nil;
    self.searchResultMessageDictionary = nil;
    self.messageDictionary = nil;
    self.toolbar = nil;
    self.searchResultIndicatorItem = nil;
    self.prevItem = nil;
    self.nextItem = nil;
    self.epmtyItem = nil;
    self.curIdxHistory = 0;
}

- (instancetype)initWithSearchResultsController:(UIViewController *)searchResultsController
{
    return [super initWithSearchResultsController:searchResultsController];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self defaultStatus];
    [self.searchResultDelegate doReloadActionForAllTableView];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [self.searchBar becomeFirstResponder];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    if ([searchText length] == 0)
    {
        [self defaultStatus];
        [self.searchResultDelegate doReloadActionForAllTableView];
    }
    else
    {
        [self getSearchData:searchText];
        
        if ([self.searchResultMessageList count] >0)
        {
            self.toolbar.items = @[self.epmtyItem, self.prevItem, self.nextItem, self.searchResultIndicatorItem];
            #if TARGET_OS_MACCATALYST
                CGFloat yAxis = self.view.frame.size.height - self.searchBar.frame.size.height;
                [self.toolbar setFrame:CGRectMake(0, yAxis, self.searchBar.frame.size.width, self.searchBar.frame.size.height)];
                [self.view addSubview:self.toolbar];
            #else
                self.searchBar.inputAccessoryView = self.toolbar;
            #endif
            self.curIdxHistory = (int)[self.searchResultMessageList count] - 1;
            
            [self setResultIndicatorTitle:@"" onlyHint:NO];
            [self.searchBar reloadInputViews];
        }
        else
        {
            self.curIdxHistory = 0;
            self.toolbar.items = @[self.epmtyItem, self.searchResultIndicatorItem];
            [self setResultIndicatorTitle:NSLocalizedString(@"No search result.", @"") onlyHint:YES];
        }
        [self updateMsgDictionary];
    }
}

-(void) doNextAction
{
    self.isGoingUp = NO;
    if (!self.isLoadingHistory)
    {
        self.curIdxHistory += 1;
        if (self.curIdxHistory > self.searchResultMessageList.count - 1)
            self.curIdxHistory = (int) self.searchResultMessageList.count - 1;
        
        if([self getMessageIndexPathForDBId:((MLMessage*)self.searchResultMessageList[self.curIdxHistory]).messageDBId] != nil)
        {
            [self setResultIndicatorTitle:@"" onlyHint:NO];
            [self.searchResultDelegate doGoSearchResultAction:((MLMessage*)self.searchResultMessageList[self.curIdxHistory]).messageDBId];
        }
        else
        {
            //Load old message
            self.isLoadingHistory = YES;
            self.curIdxHistory -= 1;            
            [self.searchResultDelegate doReloadHistoryForSearch];
            [self setResultIndicatorTitle:NSLocalizedString(@"Loading more Messages from Server", @"") onlyHint:YES];
        }
    }
    else
        [self setResultIndicatorTitle:NSLocalizedString(@"Loading more Messages from Server", @"") onlyHint:YES];
}

-(void) doPreviousAction
{
    self.isGoingUp = YES;
    if(!self.isLoadingHistory)
    {
        self.curIdxHistory -= 1;
        if (self.curIdxHistory <= 0)
            self.curIdxHistory = 0;
        
        if([self getMessageIndexPathForDBId:((MLMessage*)self.searchResultMessageList[self.curIdxHistory]).messageDBId] != nil)
        {
            [self setResultIndicatorTitle:@"" onlyHint:NO];
            [self.searchResultDelegate doGoSearchResultAction:((MLMessage*)self.searchResultMessageList[self.curIdxHistory]).messageDBId];
        }
        else
        {
            //Load old message
            self.curIdxHistory += 1;
            self.isLoadingHistory = YES;
            [self.searchResultDelegate doReloadHistoryForSearch];
            [self setResultIndicatorTitle:NSLocalizedString(@"Loading more Messages from Server", @"") onlyHint:YES];
        }
    }
    else
        [self setResultIndicatorTitle:NSLocalizedString(@"Loading more Messages from Server", @"") onlyHint:YES];
}

- (void)setResultIndicatorTitle:(NSString*)title onlyHint:(BOOL)isOnlyHint
{
    NSString* finalTitle = @"";
    
    if (!isOnlyHint)
    {
        finalTitle = [NSString stringWithFormat:@"%d/%d",(self.curIdxHistory+1), (int)self.searchResultMessageList.count];
    }
    else
    {
        finalTitle = title;
        [self.searchResultDelegate doShowLoadingHistory:finalTitle];
    }
    
    [self.searchResultIndicatorItem setTitle:finalTitle];
    [self.searchResultDelegate doReloadActionForAllTableView];
}

- (void)updateMsgDictionary
{
    [self.searchResultMessageDictionary removeAllObjects];
    for (MLMessage *msg in self.searchResultMessageList)
    {
        [self.searchResultMessageDictionary setObject:msg forKey:msg.messageDBId];
    }
}

- (BOOL)isDBIdExistent:(NSNumber*) dbId
{
    if ([self.searchResultMessageDictionary objectForKey:dbId])
    {
        return  YES;
    }
    
    return NO;
}

- (void)defaultStatus
{
    self.toolbar.items = @[];
    if (self.searchResultMessageList != nil)
        [self.searchResultMessageList removeAllObjects];
    
    if (self.searchResultMessageDictionary != nil)
        [self.searchResultMessageDictionary removeAllObjects];
    
    self.searchBar.inputAccessoryView = nil;
    [self.searchBar reloadInputViews];
}

- (void)setResultToolBar
{
    [self setResultIndicatorTitle:@"" onlyHint:NO];
}

- (void) getSearchData:(NSString*) queryText
{
    NSArray* searchResultArray = [[DataLayer sharedInstance] searchResultOfHistoryMessageWithKeyWords:queryText betweenContact:self.contact];
    [self.searchResultMessageList removeAllObjects];
    self.searchResultMessageList = [searchResultArray mutableCopy];
}

-(NSMutableAttributedString*) doSearchKeyword:(NSString*) keyword onText:(NSString*) allText andInbound:(BOOL) inDirection
{
    NSMutableAttributedString* attributedString = [[NSMutableAttributedString alloc] initWithString:allText];
    NSRange allTextRange = NSMakeRange(0, allText.length);
    
    NSRange foundRange;
    while (allTextRange.location < allText.length) {
        foundRange = [allText rangeOfString:keyword options:NSCaseInsensitiveSearch range:allTextRange];
        if (foundRange.location != NSNotFound)
        {
            allTextRange.location = foundRange.location + foundRange.length;
            allTextRange.length = allText.length - allTextRange.location;
            if (inDirection)
            {
                [attributedString addAttribute:NSBackgroundColorAttributeName value:[UIColor yellowColor] range:foundRange];
            }
            else
            {
                [attributedString addAttribute:NSBackgroundColorAttributeName value:[UIColor grayColor] range:foundRange];
            }
        }
        else
        {
            break;
        }
    }
    
    return attributedString;
}

-(void)setMessageIndexPath:(NSNumber*)idxPath withDBId:(NSNumber*)dbId
{
    [self.messageDictionary setObject:idxPath forKey:dbId];
}

-(NSNumber*) getMessageIndexPathForDBId:(NSNumber*) dbId
{
    return [self.messageDictionary objectForKey:dbId];
}

-(void)escapeSearchPressed:(UIKeyCommand*)keyCommand
{
    [self defaultStatus];
    [self.searchResultDelegate doReloadActionForAllTableView];
    [self setActive:NO];
    [self dismissViewControllerAnimated:NO completion:nil];
}

// List of custom hardware key commands
- (NSArray<UIKeyCommand *> *)keyCommands {
    return @[
            // esc
            [UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(escapeSearchPressed:)]
    ];
}
@end
