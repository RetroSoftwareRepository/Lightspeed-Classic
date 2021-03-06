/* -*- Mode: C++; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef __nsCocoaBrowserView_h__
#define __nsCocoaBrowserView_h__

#undef DARWIN
#import <Cocoa/Cocoa.h>

#include "prtypes.h"
#include "nsCOMPtr.h"

@class CHBrowserView;
@class CertificateItem;

class CHBrowserListener;
class nsIDOMWindow;
class nsIWebBrowser;
class nsIDocShell;
class nsIDOMNode;
class nsIDOMPopupBlockedEvent;
class nsIDOMEvent;
class nsIPrintSettings;
class nsIURI;
class nsISupports;
class nsISecureBrowserUI;
class nsIDOMNSEvent;
class nsIDOMSimpleGestureEvent;

// Page load outcomes: succeeded means the page loaded successfully,
// failed means there was an error (e.g., 404), and blocked means
// that the page was flagged as possible phishing/malware (in which
// case the user is seeing our warning overlay, rather than the page).
typedef enum
{
  eRequestSucceeded,
  eRequestFailed,
  eRequestBlocked
} ERequestStatus;

typedef enum {
  eSafeBrowsingNotBlocked = 0,
  eSafeBrowsingBlockedAsPhishing,
  eSafeBrowsingBlockedAsMalware
} ESafeBrowsingBlockedReason;

// Protocol implemented by anyone interested in progress
// related to a BrowserView. A listener should explicitly
// register itself with the view using the addListener
// method.
@protocol CHBrowserListener

- (void)onLoadingStarted;
- (void)onLoadingCompleted:(BOOL)succeeded;
// Called when each resource on a page (the main HTML plus any subsidiary
// resources such as images and style sheets) starts ond finishes.
- (void)onResourceLoadingStarted:(NSValue*)resourceIdentifier;
- (void)onResourceLoadingCompleted:(NSValue*)resourceIdentifier;
// Invoked regularly as data associated with a page streams
// in. If the total number of bytes expected is unknown,
// maxBytes is -1.
- (void)onProgressChange:(long)currentBytes outOf:(long)maxBytes;
- (void)onProgressChange64:(long long)currentBytes outOf:(long long)maxBytes;

- (void)onLocationChange:(NSString*)urlSpec isNewPage:(BOOL)newPage requestStatus:(ERequestStatus)requestStatus;
- (void)onStatusChange:(NSString*)aMessage;
- (void)onSecurityStateChange:(unsigned long)newState;
// Called when a context menu should be shown.
- (void)onShowContextMenu:(int)flags domEvent:(nsIDOMEvent*)aEvent domNode:(nsIDOMNode*)aNode;
// Called when a tooltip should be shown or hidden
- (void)onShowTooltip:(NSPoint)where withText:(NSString*)text;
- (void)onHideTooltip;
// Called when a popup is blocked
- (void)onPopupBlocked:(nsIDOMPopupBlockedEvent*)data;
// Called when Flashblock whitelist is checked
- (void)onFlashblockCheck:(nsIDOMEvent*)inEvent;
// Called when Silverlight block preference is checked
- (void)onSilverblockCheck:(nsIDOMEvent*)inEvent;
// Called when a "shortcut icon" link element is noticed
- (void)onFoundShortcutIcon:(NSString*)inIconURI;
// Called when a feed link element is noticed
- (void)onFeedDetected:(NSString*)inFeedURI feedTitle:(NSString*)inFeedTitle;
// Called when a search plugin link element is noticed.
- (void)onSearchPluginDetected:(NSURL*)pluginURL mimeType:(NSString*)pluginMIMEType displayName:(NSString*)pluginName;
// Called when an XUL element was activated (e.g. clicked) in the content area, 
// typically on an about: page.
- (void)onXULCommand:(nsIDOMNSEvent*)aDOMEvent;
// Called when a gesture event occurs in the content area
- (void)onGestureEvent:(nsIDOMSimpleGestureEvent*)simpleGestureEvent;

@end

typedef enum {
  NSStatusTypeScript            = 0x0001,
  NSStatusTypeScriptDefault     = 0x0002,
  NSStatusTypeLink              = 0x0003,
} NSStatusType;

@protocol CHBrowserContainer

- (void)setStatus:(NSString *)statusString ofType:(NSStatusType)type;
- (NSString *)title;
- (void)setTitle:(NSString *)title;
// Set the dimensions of our NSView. The container might need to do
// some adjustment, so the view doesn't do it directly.
- (void)sizeBrowserTo:(NSSize)dimensions;

// Create a new browser container window and return the contained view. 
- (CHBrowserView*)createBrowserWindow:(unsigned int)mask;
// Return the view of the current window, or perhaps a new tab within that window,
// in which to load the request.
- (CHBrowserView*)reuseExistingBrowserWindow:(unsigned int)mask;

// Return whether the container prefers to create new windows or to re-use
// the existing one (will return YES if implementing "single-window mode")
- (BOOL)shouldReuseExistingWindow;
- (int)respectWindowOpenCallsWithSizeAndPosition;

- (NSMenu*)contextMenu;
- (NSWindow*)nativeWindow;

// Gecko wants to close the "window" associated with this instance. Some
// embedding apps might want to multiplex multiple gecko views in one
// window (tabbed browsing). This gives them the chance to change the
// behavior.
- (void)closeBrowserWindow;

// Handle window.blur; send the window to the back and resign focus.
- (void)sendBrowserWindowToBack;

// Called before and after a prompt is shown for the contained view
- (void)willShowPrompt;
- (void)didDismissPrompt;

// Keyboard focus should be transferred to the next eligible view before or after
// the browser. An argument of YES indicates tab was pressed after the last Gecko
// element had been focused; NO if shift-tab with the first element focused.
- (void)tabOutOfBrowser:(BOOL)tabbingForward;

@end

enum {
  NSLoadFlagsNone                   = 0x0000,
  NSLoadFlagsDontPutInHistory       = 0x0010,
  NSLoadFlagsReplaceHistoryEntry    = 0x0020,
  NSLoadFlagsBypassCacheAndProxy    = 0x0040,
  NSLoadFlagsAllowThirdPartyFixup   = 0x2000,
  NSLoadFlagsBypassClassifier       = 0x10000
}; 

enum {
  NSStopLoadNetwork   = 0x01,
  NSStopLoadContent   = 0x02,
  NSStopLoadAll       = 0x03  
};

typedef enum {
  CHSecurityInsecure     = 0,
  CHSecuritySecure       = 1,
  CHSecurityBroken       = 2     // or mixed content
} CHSecurityStatus;

typedef enum {
  CHSecurityNone          = 0,
  CHSecurityLow           = 1,
  CHSecurityMedium        = 2,     // key strength < 90 bit
  CHSecurityHigh          = 3
} CHSecurityStrength;

extern const char* const kPlainTextMIMEType;
extern const char* const kHTMLMIMEType;

@interface CHBrowserView : NSView 
{
  nsIWebBrowser*        _webBrowser;
  CHBrowserListener*    _listener;
  NSWindow*             mWindow;

  nsIPrintSettings*     mPrintSettings; // we own this
  BOOL                  mUseGlobalPrintSettings;
}

// class method to get at the browser view for a given nsIDOMWindow
+ (CHBrowserView*)browserViewFromDOMWindow:(nsIDOMWindow*)inWindow;

// NSView overrides
- (id)initWithFrame:(NSRect)frame;
- (id)initWithFrame:(NSRect)frame andWindow:(NSWindow*)aWindow;

- (void)dealloc;
- (void)setFrame:(NSRect)frameRect;

// nsIWebBrowser methods
- (void)addListener:(id <CHBrowserListener>)listener;
- (void)removeListener:(id <CHBrowserListener>)listener;
- (void)setContainer:(NSView<CHBrowserListener, CHBrowserContainer>*)container;
- (already_AddRefed<nsIDOMWindow>)contentWindow;	// addrefs

// nsIWebNavigation methods
- (void)loadURI:(NSString *)urlSpec referrer:(NSString*)referrer flags:(unsigned int)flags allowPopups:(BOOL)inAllowPopups;
- (void)reload:(unsigned int)flags;
- (void)goBack;
- (BOOL)canGoBack;
- (void)goForward;
- (BOOL)canGoForward;
- (void)stop:(unsigned int)flags;   // NSStop flags
- (void)goToSessionHistoryIndex:(int)index;

- (NSString*)currentURI;

- (NSString*)pageLocation;  // from window.location. can differ from the document's URI, and possibly from currentURI
- (NSString*)pageLocationHost;
- (NSString*)pageTitle;
- (NSDate*)pageLastModifiedDate;
- (BOOL)isTextBasedContent;
- (BOOL)isImageBasedContent;

// nsIWebBrowserSetup methods
- (void)setProperty:(unsigned int)property toValue:(unsigned int)value;

- (void)saveDocument:(BOOL)focusedFrame filterView:(NSView*)aFilterView;
- (void)saveURL:(NSView*)aFilterView url: (NSString*)aURLSpec suggestedFilename: (NSString*)aFilename;

- (void)printDocument;
- (void)pageSetup;

- (BOOL)findInPageWithPattern:(NSString*)inText caseSensitive:(BOOL)inCaseSensitive
            wrap:(BOOL)inWrap backwards:(BOOL)inBackwards;

- (BOOL)findInPage:(BOOL)inBackwards;
- (NSString*)lastFindText;

-(BOOL)validateMenuItem: (NSMenuItem*)aMenuItem;

-(IBAction)cut:(id)aSender;
-(BOOL)canCut;
-(IBAction)copy:(id)aSender;
-(BOOL)canCopy;
-(IBAction)paste:(id)aSender;
-(BOOL)canPaste;
-(IBAction)delete:(id)aSender;
-(BOOL)canDelete;
-(IBAction)selectAll:(id)aSender;

// Returns the currently selected text as a NSString. 
- (NSString*)selectedText;

-(IBAction)undo:(id)aSender;
-(IBAction)redo:(id)aSender;

- (BOOL)canUndo;
- (BOOL)canRedo;

- (void)makeTextBigger;
- (void)makeTextSmaller;
- (void)makeTextDefaultSize;

- (BOOL)canMakeTextBigger;
- (BOOL)canMakeTextSmaller;
- (BOOL)isTextDefaultSize;

- (void)makePageBigger;
- (void)makePageSmaller;
- (void)makePageDefaultSize;

- (BOOL)canMakePageBigger;
- (BOOL)canMakePageSmaller;
- (BOOL)isPageDefaultSize;

- (void)pageUp;
- (void)pageDown;

// Verifies that the browser view can be unloaded (e.g., validates
// onbeforeunload handlers). Should be called before any action that would
// destroy the browser view.
- (BOOL)shouldUnload;

// ideally these would not have to be called from outside the CHBrowerView, but currently
// the cocoa impl of nsIPromptService is at the app level, so it needs to call down
// here. We'll just turn around and call the CHBrowserContainer methods
- (void)doBeforePromptDisplay;
- (void)doAfterPromptDismissal;

// Makes Gecko active. If this is called before Gecko is capable of becoming
// active, then this will return NO to indicate that the client should try again
// later in the loading process.
- (BOOL)setActive:(BOOL)aIsActive;

- (NSMenu*)contextMenu;
- (NSWindow*)nativeWindow;

- (void)destroyWebBrowser;
// Returns the underlying nsIWebBrowser, addref'd
- (nsIWebBrowser*)webBrowser;
- (void)setWebBrowser:(nsIWebBrowser*)browser;
- (CHBrowserListener*)cocoaBrowserListener;

- (BOOL)isTextFieldFocused;
- (BOOL)isPluginFocused;

- (NSString*)focusedURLString;

// Gets an NSImage representation of the currently visible section of the page.
- (NSImage*)snapshot;

// charset
- (IBAction)reloadWithNewCharset:(NSString*)charset;
- (NSString*)currentCharset;

// access to page text as a given MIME type
- (NSString*)pageTextForSelection:(BOOL)selection inFormat:(const char*)format;

// security
- (BOOL)hasSSLStatus;   // if NO, then the following methods all return empty values.
- (unsigned int)secretKeyLength;
- (NSString*)cipherName;
- (CHSecurityStatus)securityStatus;
- (CHSecurityStrength)securityStrength;
- (CertificateItem*)siteCertificate;

// Gets the current page descriptor. If |byFocus| is true, the page descriptor
// is for the currently focused frame; if not, it's for the top-level frame.
- (already_AddRefed<nsISupports>)pageDescriptorByFocus:(BOOL)byFocus;
- (void)setPageDescriptor:(nsISupports*)aDesc displayType:(PRUint32)aDisplayType;

@end

#endif // __nsCocoaBrowserView_h__
