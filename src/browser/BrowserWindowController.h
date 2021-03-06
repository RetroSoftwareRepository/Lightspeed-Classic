/* -*- Mode: C++; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>
#import "BrowserWrapper.h"
#import "MainController.h"

class nsIURIFixup;
class nsIBrowserHistory;
class nsIDOMEvent;
class nsIDOMNode;
class nsIWebNavigation;

class BWCDataOwner;

//
// ThrobberHandler
//
// A helper class that handles animating the throbber when it's alive. It starts
// automatically when you init it. To get it to stop, call |stopThrobber|. Calling
// |release| is not enough because the timer used to animate the images holds a strong
// ref back to the handler so it won't go away unless you break that cycle manually with
// |stopThrobber|.
//
// This class must be separate from BrowserWindowController else the
// same thing will happen there and the timer will cause it to stay alive and continue
// loading the webpage even though the window has gone away.
//
@interface ThrobberHandler : NSObject
{
  NSTimer* mTimer;
  NSArray* mImages;
  unsigned int mFrame;
}

// public
- (id)initWithToolbarItem:(NSToolbarItem*)inButton images:(NSArray*)inImages;
- (void)stopThrobber;

// internal
- (void)startThrobber;
- (void)pulseThrobber:(id)aSender;

@end

#pragma mark -

typedef enum
{
  eAppendTabs,
  eReplaceTabs,
  eReplaceFromCurrentTab
	  
} ETabOpenPolicy;

typedef enum  {
  eDestinationNewWindow = 0,
  eDestinationNewTab,
  eDestinationCurrentView
} EOpenDestination;

@class CHBrowserView;
@class BookmarkViewController;
@class BookmarkToolbar;
@class BrowserTabView;
@class PageProxyIcon;
@class BrowserContentView;
@class BrowserTabViewItem;
@class AutoCompleteTextField;
@class ExtendedSplitView;
@class WebSearchField;

@interface BrowserWindowController : NSWindowController<BrowserUIDelegate, BrowserUICreationDelegate>
{
  IBOutlet BrowserTabView*    mTabBrowser;
  IBOutlet ExtendedSplitView* mLocationToolbarView;     // parent splitter of location and search, strong
  IBOutlet AutoCompleteTextField* mURLBar;
  IBOutlet NSTextField*       mStatus;
  IBOutlet NSProgressIndicator* mProgress;
  IBOutlet NSWindow*          mLocationSheetWindow;
  IBOutlet NSTextField*       mLocationSheetURLField;
  IBOutlet NSView*            mStatusBar;     // contains the status text, progress bar, and lock
  IBOutlet BrowserContentView*  mContentView;
  
  IBOutlet BookmarkToolbar*     mPersonalToolbar;

  IBOutlet WebSearchField*      mSearchBar;
  IBOutlet WebSearchField*      mSearchSheetTextField;
  IBOutlet NSWindow*            mSearchSheetWindow;
  
  // Context menu outlets.
  IBOutlet NSMenu*              mPageMenu;
  IBOutlet NSMenu*              mImageMenu;
  IBOutlet NSMenu*              mInputMenu;
  IBOutlet NSMenu*              mLinkMenu;
  IBOutlet NSMenu*              mMailToLinkMenu;
  IBOutlet NSMenu*              mImageLinkMenu;
  IBOutlet NSMenu*              mImageMailToLinkMenu;
  IBOutlet NSMenu*              mTabMenu;
  IBOutlet NSMenu*              mTabBarMenu;

  // Context menu item outlets
  IBOutlet NSMenuItem*          mBackItem;
  IBOutlet NSMenuItem*          mForwardItem;
  IBOutlet NSMenuItem*          mCopyItem;
  
  BOOL mInitialized;

  NSString* mPendingURL;
  NSString* mPendingReferrer;
  BOOL mPendingActivate;
  BOOL mPendingAllowPopups;
  
  BrowserWrapper*               mBrowserView;   // browser wrapper of frontmost tab

  // The browser view that the user was on before a prompt forced a switch (weak)
  BrowserWrapper*               mLastBrowserView;
  
  BOOL mMoveReentrant;
  BOOL mClosingWindow;

  BOOL mShouldAutosave;
  BOOL mSuppressInitialPageLoad;

  BOOL mWindowClosesQuietly;  // if YES, don't warn on multi-tab window close
  
  unsigned int mChromeMask; // Indicates which parts of the window to show (e.g., don't show toolbars)

  // Needed for correct window zooming
  NSRect mLastFrameSize;
  BOOL mShouldZoom;

  // C++ object that holds owning refs to XPCOM objects (and related data)
  BWCDataOwner*               mDataOwner;
  
  // Throbber state variables.
  ThrobberHandler* mThrobberHandler;
  NSArray* mThrobberImages;

  // Funky field editor for URL bar
  NSTextView *mURLFieldEditor;

  NSString *mLastKnownPreferredSearchEngine;

  // Pinch gesture handling.
  float mTotalMagnifyGestureAmount;  // Total delta-z for the current pinch.
  int mCurrentZoomStepDelta;  // Zoom steps taken during the current pinch.
}

- (BrowserTabView*)tabBrowser;
- (BrowserWrapper*)browserWrapper;

- (void)loadURL:(NSString*)aURLSpec referrer:(NSString*)aReferrer focusContent:(BOOL)focusContent allowPopups:(BOOL)inAllowPopups;
- (void)loadURL:(NSString*)aURLSpec;

- (void)focusURLBar;

- (void)showBlockedPopups:(nsIArray*)blockedSites whitelistingSource:(BOOL)shouldWhitelist;
- (void)blacklistPopupsFromURL:(NSString*)inURL;

  // call to update feed detection in a page
- (void)showFeedDetected:(BOOL)inDetected;
- (IBAction)openFeedPrefPane:(id)sender;

- (void)performAppropriateLocationAction;
- (IBAction)goToLocationFromToolbarURLField:(id)sender;
- (void)beginLocationSheet;
- (IBAction)endLocationSheet:(id)sender;
- (IBAction)cancelLocationSheet:(id)sender;

- (void)performAppropriateSearchAction;
- (void)focusSearchBar;
- (void)beginSearchSheet;
- (IBAction)endSearchSheet:(id)sender;
- (IBAction)cancelSearchSheet:(id)sender;
- (IBAction)manageSearchEngines:(id)sender;
- (IBAction)findSearchEngines:(id)sender;

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize;

// Gets/sets the visibility of the bookmark bar.
- (BOOL)bookmarkBarIsVisible;
- (void)setBookmarkBarIsVisible:(BOOL)visible;

// Gets/sets the visibility of the status bar.
- (BOOL)statusBarIsVisible;
- (IBAction)setStatusBarIsVisible:(BOOL)visible;

- (IBAction)viewSource:(id)aSender;			// focussed frame or page
- (IBAction)viewPageSource:(id)aSender;	// top-level page

- (void)saveDocument:(BOOL)focusedFrame filterView:(NSView*)aFilterView;
- (void)saveURL:(NSView*)aFilterView url: (NSString*)aURLSpec suggestedFilename: (NSString*)aFilename;

- (IBAction)printDocument:(id)aSender;
- (IBAction)pageSetup:(id)aSender;
- (IBAction)searchFieldTriggered:(id)aSender;
- (IBAction)searchForSelection:(id)aSender;
- (IBAction)sendURL:(id)aSender;
- (IBAction)sendURLFromLink:(id)aSender;

- (void)startThrobber;
- (void)stopThrobber;
- (void)clickThrobber:(id)aSender;

- (void)find:(id)aSender;

- (BOOL)validateActionBySelector:(SEL)action;
// Returns YES if window-targeting actions should be disabled/prevented
// (e.g., if a sheet is attached to the window).
- (BOOL)shouldSuppressWindowActions;

- (BOOL)canMakeTextBigger;
- (BOOL)canMakeTextSmaller;
- (BOOL)canMakeTextDefaultSize;
- (IBAction)makeTextBigger:(id)aSender;
- (IBAction)makeTextSmaller:(id)aSender;
- (IBAction)makeTextDefaultSize:(id)aSender;

// Returns YES if the current page is reasonable to report to the safe browsing
// data provider as a suspected phishing site.
- (BOOL)canReportCurrentPageAsPhishing;

- (BOOL)canMakePageBigger;
- (BOOL)canMakePageSmaller;
- (BOOL)canMakePageDefaultSize;
- (IBAction)makePageBigger:(id)aSender;
- (IBAction)makePageSmaller:(id)aSender;
- (IBAction)makePageDefaultSize:(id)aSender;

- (IBAction)getInfo:(id)sender;

- (BOOL)shouldShowBookmarkToolbar;

- (IBAction)manageBookmarks: (id)aSender;
- (IBAction)manageHistory: (id)aSender;

- (BOOL)bookmarkManagerIsVisible;
- (BOOL)canHideBookmarks;
- (BOOL)singleBookmarkIsSelected;

- (IBAction)newTab:(id)sender;
- (IBAction)closeCurrentTab:(id)sender;
- (IBAction)previousTab:(id)sender;
- (IBAction)nextTab:(id)sender;

- (IBAction)closeSendersTab:(id)sender;
- (IBAction)closeOtherTabs:(id)sender;
- (IBAction)reloadAllTabs:(id)sender;
- (IBAction)reloadSendersTab:(id)sender;
- (IBAction)moveTabToNewWindow:(id)sender;

- (IBAction)back:(id)aSender;
- (IBAction)forward:(id)aSender;
- (IBAction)reload:(id)aSender;
- (IBAction)stop:(id)aSender;
- (IBAction)home:(id)aSender;
- (void)stopAllPendingLoads;

- (IBAction)toggleTabThumbnailView:(id)sender;
- (BOOL)tabThumbnailViewIsVisible;

- (IBAction)reloadWithNewCharset:(NSString*)charset;
- (NSString*)currentCharset;

- (IBAction)frameToNewWindow:(id)sender;
- (IBAction)frameToNewTab:(id)sender;
- (IBAction)frameToThisWindow:(id)sender;

// Reports the current page as one suspected of phishing.
- (IBAction)reportPhishingPage:(id)aSender;

- (BrowserWindowController*)openNewWindowWithURL: (NSString*)aURLSpec referrer:(NSString*)aReferrer loadInBackground: (BOOL)aLoadInBG allowPopups:(BOOL)inAllowPopups;
- (void)openNewTabWithURL: (NSString*)aURLSpec referrer: (NSString*)aReferrer loadInBackground: (BOOL)aLoadInBG allowPopups:(BOOL)inAllowPopups setJumpback:(BOOL)inSetJumpback;

- (CHBrowserView*)createNewTabBrowser:(BOOL)inLoadInBG;

- (void)openURLArray:(NSArray*)urlArray tabOpenPolicy:(ETabOpenPolicy)tabPolicy allowPopups:(BOOL)inAllowPopups;
- (void)openURLArrayReplacingTabs:(NSArray*)urlArray closeExtraTabs:(BOOL)closeExtra allowPopups:(BOOL)inAllowPopups;

-(BrowserTabViewItem*)createNewTabItem;

- (void)closeBrowserWindow:(BrowserWrapper*)inBrowser;
- (void)sendBrowserWindowToBack:(BrowserWrapper*)inBrowser;

- (void)willShowPromptForBrowser:(BrowserWrapper*)inBrowser;
- (void)didDismissPromptForBrowser:(BrowserWrapper*)inBrowser;

-(void)autosaveWindowFrame;
-(void)disableAutosave;
-(void)disableLoadPage;

-(void)setChromeMask:(unsigned int)aMask;
-(unsigned int)chromeMask;

-(BOOL)hasFullBrowserChrome;

// Called when a context menu should be shown.
- (void)onShowContextMenu:(int)flags domEvent:(nsIDOMEvent*)aEvent domNode:(nsIDOMNode*)aNode;
- (NSMenuItem*)prepareAddToAddressBookMenuItem:(NSString*)emailAddress;
- (NSMenu*)contextMenu;
- (NSArray*)mailAddressesInContextMenuLinkNode;
- (NSString*)contextMenuNodeHrefText;

// Context menu methods
- (IBAction)openLinkInNewWindow:(id)aSender;
- (IBAction)openLinkInNewTab:(id)aSender;
- (void)openLinkInNewWindowOrTab: (BOOL)aUseWindow;
- (IBAction)addToAddressBook:(id)aSender;
- (IBAction)copyAddressToClipboard:(id)aSender;

- (IBAction)savePageAs:(id)aSender;
- (IBAction)saveFrameAs:(id)aSender;
- (IBAction)saveLinkAs:(id)aSender;
- (IBAction)saveImageAs:(id)aSender;

- (IBAction)viewOnlyThisImage:(id)aSender;

- (IBAction)showPageInfo:(id)sender;
- (IBAction)showBookmarksInfo:(id)sender;
- (IBAction)showSiteCertificate:(id)sender;

- (IBAction)addBookmark:(id)aSender;
- (IBAction)addTabGroup:(id)aSender;
- (IBAction)addBookmarkWithoutPrompt:(id)aSender;
- (IBAction)addTabGroupWithoutPrompt:(id)aSender;
- (IBAction)addBookmarkForLink:(id)aSender;
- (IBAction)addBookmarkFolder:(id)aSender;
- (IBAction)addBookmarkSeparator:(id)aSender;

- (IBAction)copyLinkLocation:(id)aSender;
- (IBAction)copyImage:(id)sender;
- (IBAction)copyImageLocation:(id)sender;

- (IBAction)unblockFlashFromCurrentDomain:(id)sender;

- (BOOL)windowClosesQuietly;
- (void)setWindowClosesQuietly:(BOOL)inClosesQuietly;

// called when the internal window focus has changed
// this allows us to dispatch activate and deactivate events as necessary
- (void) focusChangedFrom:(NSResponder*) oldResponder to:(NSResponder*) newResponder;

// Called to get cached versions of our security icons
+ (NSImage*) insecureIcon;
+ (NSImage*) secureIcon;
+ (NSImage*) brokenIcon;

// cache the toolbar defaults we parse from a plist
+ (NSArray*) toolbarDefaults;

// Get the correct load-in-background behvaior for the given destination based
// on prefs and the state of the shift key. If possible, aSender's
// keyEquivalentModifierMask is used to determine the shift key's state.
// Otherwise (if aSender doesn't respond to keyEquivalentModifierMask is nil)
// it uses the current event's modifier flags.
+ (BOOL)shouldLoadInBackgroundForDestination:(EOpenDestination)destination
                                      sender:(id)sender;

// Accessor to get the proxy icon view
- (PageProxyIcon *)proxyIconView;

// Accessor for the bm data source
- (BookmarkViewController *)bookmarkViewController;

// Browser view of the frontmost tab (nil if bookmarks are showing?)
- (CHBrowserView*)activeBrowserView;

// return a weak reference to the current web navigation object. Callers should
// not hold onto this for longer than the current call unless they addref it.
- (nsIWebNavigation*) currentWebNavigation;

// handle command-return in location or search field
- (BOOL)handleCommandReturn:(BOOL)aShiftIsDown;

// Load the item in the bookmark bar given by |inIndex| using the given behavior.
- (BOOL)loadBookmarkBarIndex:(unsigned short)inIndex openBehavior:(EBookmarkOpenBehavior)inBehavior;

// Reveal the bookmarkItem in the manager
- (void)revealBookmark:(BookmarkItem*)anItem;

@end
