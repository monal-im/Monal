//
//  MLSearchViewController.h
//  Monal
//
//  Created by jimtsai (poormusic2001@gmail.com) on 2020/9/23.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <monalxmpp/MLContact.h>
#import <monalxmpp/DataLayer.h>

@protocol SearchResultDelegate
- (void) doGoSearchResultAction:(NSNumber*_Nullable) nextDBId;
- (void) doReloadActionForAllTableView;
- (void) doReloadHistoryForSearch;
- (void) doGetMsgData;
- (void) doShowLoadingHistory:(NSString* _Nonnull) title;
@end

NS_ASSUME_NONNULL_BEGIN

@interface MLSearchViewController : UISearchController <UISearchBarDelegate>
@property (nonatomic, strong) MLContact *contact;
@property (nonatomic, weak) NSString *jid;
@property (nonatomic, weak) id <SearchResultDelegate> searchResultDelegate;
@property (nonatomic) BOOL isLoadingHistory;
@property (nonatomic) BOOL isGoingUp;


- (void) getSearchData:(NSString*) queryText;
- (NSMutableAttributedString*) doSearchKeyword:(NSString*) keyword onText:(NSString*) allText andInbound:(BOOL) inDirection;
- (BOOL) isDBIdExistent:(NSNumber*) dbId;
- (void) setResultToolBar;
- (void) setMessageIndexPath:(NSNumber*)idxPath withDBId:(NSNumber*)dbId;
- (NSNumber*) getMessageIndexPathForDBId:(NSNumber*)dbId;
- (void) doNextAction;
- (void) doPreviousAction;
@end

NS_ASSUME_NONNULL_END
