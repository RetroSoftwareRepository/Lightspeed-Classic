/* -*- Mode: C++; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#import "NSString+Gecko.h"
#import "NSPasteboard+Utils.h"
#import "NSDate+Utils.h"

#import "CHSelectHandler.h"

#include "nsCWebBrowser.h"
#include "nsIBaseWindow.h"
#include "nsIWebNavigation.h"
#include "nsIWebBrowserSetup.h"
#include "nsIWebProgressListener.h"
#include "nsComponentManagerUtils.h"
#include "nsIDocCharset.h"

#include "nsIURI.h"
#include "nsIURIFixup.h"
#include "nsIDocument.h"
#include "nsIDOMWindow.h"
#include "nsPIDOMWindow.h"
#include "nsPIDOMEventTarget.h"
#include "nsIDOMEventTarget.h"
#include "nsIWidget.h"
#include "nsIPrefBranch.h"
#include "nsIDOMNSEventTarget.h"

// Printing
#include "nsIWebBrowserPrint.h"
#include "nsIPrintSettings.h"
#include "nsIPrintingPromptService.h"
#include "nsIPrintSettingsService.h"

// bigger/smaller text
#include "nsPIDOMWindow.h"
#include "nsIDocShell.h"
#include "nsIMarkupDocumentViewer.h"
#include "nsIContentViewer.h"

// nsIDOMWindow->CHBrowserView
#include "nsIWindowWatcher.h"
#include "nsIEmbeddingSiteWindow.h"

// Saving of links/images/docs
#include "nsIWebBrowserFocus.h"
#include "nsIDOMNSDocument.h"
#include "nsIDOMHTMLDocument.h"
#include "nsIDOMNSHTMLDocument.h"
#include "nsIDOMLocation.h"
#include "nsIWebBrowserPersist.h"
#include "nsIProperties.h"
#include "nsISHistory.h"
#include "nsIHistoryEntry.h"
#include "nsISHEntry.h"
#include "nsNetUtil.h"
#include "SaveHeaderSniffer.h"
#include "nsIWebPageDescriptor.h"

// Find in page
#include "nsIWebBrowserFind.h"
#include "nsISelection.h"

// Focus accessors
#include "nsFocusManager.h"
#include "nsIDOMElement.h"

// Focus tests
#include "nsIDOMHTMLInputElement.h"
#include "nsIDOMHTMLTextAreaElement.h"
#include "nsIDOMHTMLEmbedElement.h"
#include "nsIDOMHTMLObjectElement.h"
#include "nsIDOMHTMLAppletElement.h"

// security
#include "nsISecureBrowserUI.h"
#include "nsISSLStatusProvider.h"
#include "nsISSLStatus.h"
#include "nsIX509Cert.h"

#import "CHBrowserView.h"

#import "CHBrowserService.h"
#import "CHBrowserListener.h"

// this adds a dependency on camino/src/security
#import "CertificateItem.h"

// Updating the Find Bar UI
#import "FindNotifications.h"

#import "mozView.h"

// Cut/copy/paste
#include "nsIClipboardCommands.h"
#include "nsIInterfaceRequestorUtils.h"

// Undo/redo
#include "nsICommandManager.h"
#include "nsICommandParams.h"

// Thumbnailing
#include "gfxContext.h"
#include "gfxQuartzSurface.h"
#include "nsPresContext.h"

#include "GeckoUtils.h"


const char kPersistContractID[] = "@mozilla.org/embedding/browser/nsWebBrowserPersist;1";
const char kDirServiceContractID[] = "@mozilla.org/file/directory_service;1";

const char* const kPlainTextMIMEType = "text/plain";
const char* const kHTMLMIMEType = "text/html";

#define DEFAULT_TEXT_ZOOM 1.0f
#define MIN_TEXT_ZOOM 0.01f
#define MAX_TEXT_ZOOM 20.0f

#define PAGE_ZOOM_INCREMENT 0.125f
#define DEFAULT_PAGE_ZOOM 1.0f
#define MIN_PAGE_ZOOM 0.25f
#define MAX_PAGE_ZOOM 5.0f

@interface CHBrowserView(Private)

- (id<CHBrowserContainer>)browserContainer;
- (nsIContentViewer*)contentViewer;		// addrefs return value
- (float)textZoom;
- (float)pageZoom;
- (void)incrementTextZoom:(float)increment min:(float)min max:(float)max;
- (void)incrementPageZoom:(float)increment min:(float)min max:(float)max;
- (nsIDocShell*)docShell;    // does NOT addref
- (NSString*)selectedText;
- (void)postFindStatusNotification:(BOOL)success;
- (already_AddRefed<nsIDOMWindow>)focussedDOMWindow;
- (already_AddRefed<nsIDOMElement>)focusedDOMElement;
- (already_AddRefed<nsISecureBrowserUI>)secureBrowserUI;
- (NSString*)locationFromDOMWindow:(nsIDOMWindow*)inDOMWindow;
- (void)ensurePrintSettings;
- (void)savePrintSettings;
- (BOOL)isPasswordFieldFocused;
- (void)collapseSelection;

@end

#pragma mark -

@implementation CHBrowserView

+ (CHBrowserView*)browserViewFromDOMWindow:(nsIDOMWindow*)inWindow
{
  if (!inWindow)
    return nil;

  // make sure we get the root window (e.g. for subframes in frameset)
  nsCOMPtr<nsIDOMWindow> topWindow;
  inWindow->GetTop(getter_AddRefs(topWindow));
  if (!topWindow)
    return nil;

  nsCOMPtr<nsIWindowWatcher> watcher(do_GetService("@mozilla.org/embedcomp/window-watcher;1"));
  if (!watcher)
    return nil;

  nsCOMPtr<nsIWebBrowserChrome> chrome;
  watcher->GetChromeForWindow(topWindow, getter_AddRefs(chrome));
  if (!chrome)
    return nil;

  nsCOMPtr<nsIEmbeddingSiteWindow> siteWindow(do_QueryInterface(chrome));
  if (!siteWindow)
    return nil;

  CHBrowserView* browserView;
  nsresult rv = siteWindow->GetSiteWindow((void**)&browserView);
  if (NS_FAILED(rv))
    return nil;
    
  return browserView;
}


- (id)initWithFrame:(NSRect)frame andWindow:(NSWindow*)aWindow
{
  mWindow = aWindow;
  return [self initWithFrame:frame];
}


- (id)initWithFrame:(NSRect)frame
{
  if ( (self = [super initWithFrame:frame]) )
  {
    nsresult rv = CHBrowserService::InitEmbedding();
    if (NS_FAILED(rv)) {
      // XXX need to throw
    }

    _listener = new CHBrowserListener(self);
    NS_ADDREF(_listener);

    // Create the web browser instance
    nsCOMPtr<nsIWebBrowser> browser = do_CreateInstance(NS_WEBBROWSER_CONTRACTID, &rv);
    if (NS_FAILED(rv)) {
      // XXX need to throw
    }

    _webBrowser = browser;
    NS_ADDREF(_webBrowser);

    // Set the container nsIWebBrowserChrome
    _webBrowser->SetContainerWindow(static_cast<nsIWebBrowserChrome *>(_listener));

    // Register as a listener for web progress
    nsCOMPtr<nsIWeakReference> weak = do_GetWeakReference(static_cast<nsIWebProgressListener*>(_listener));
    _webBrowser->AddWebBrowserListener(weak, NS_GET_IID(nsIWebProgressListener));

    // Hook up the widget hierarchy with us as the parent
    nsCOMPtr<nsIBaseWindow> baseWin = do_QueryInterface(_webBrowser);
    baseWin->InitWindow((NSView*)self, nsnull, 0, 0, (int)frame.size.width, (int)frame.size.height);
    baseWin->Create();

    // The value of mUseGlobalPrintSettings can't change during our lifetime. 
    nsCOMPtr<nsIPrefBranch> pref(do_GetService("@mozilla.org/preferences-service;1"));
    PRBool tempBool = PR_TRUE;
    pref->GetBoolPref("print.use_global_printsettings", &tempBool);
    mUseGlobalPrintSettings = tempBool;

    // hookup the listener for creating our own native menus on <SELECTS>
    CHSelectHandler* selectHandler = new CHSelectHandler();
    if (!selectHandler)
      return nil;

    nsCOMPtr<nsIDOMWindow> contentWindow = [self contentWindow];
    nsCOMPtr<nsPIDOMWindow> piWindow(do_QueryInterface(contentWindow));
    if (piWindow) {
      nsPIDOMEventTarget *chromeHandler = piWindow->GetChromeEventHandler();
      if (chromeHandler) {
        chromeHandler->AddEventListenerByIID((nsIDOMMouseListener*)selectHandler, NS_GET_IID(nsIDOMMouseListener));
        chromeHandler->AddEventListenerByIID((nsIDOMKeyListener*)selectHandler, NS_GET_IID(nsIDOMKeyListener));
      }

      // register the CHBrowserListener as an event listener for popup-blocking events,
      // link-added events, and error page (XUL content activated) command events.
      nsCOMPtr<nsIDOMEventTarget> eventTarget = do_QueryInterface(chromeHandler);
      if (eventTarget) {
        rv = eventTarget->AddEventListener(NS_LITERAL_STRING("DOMPopupBlocked"),
                                           static_cast<nsIDOMEventListener*>(_listener), PR_FALSE);
        NS_ASSERTION(NS_SUCCEEDED(rv), "AddEventListener failed");

        rv = eventTarget->AddEventListener(NS_LITERAL_STRING("DOMLinkAdded"),
                                           static_cast<nsIDOMEventListener*>(_listener), PR_FALSE);
        NS_ASSERTION(NS_SUCCEEDED(rv), "AddEventListener failed");

        rv = eventTarget->AddEventListener(NS_LITERAL_STRING("popupshowing"),
                                           static_cast<nsIDOMEventListener*>(_listener), PR_FALSE);
        NS_ASSERTION(NS_SUCCEEDED(rv), "AddEventListener failed");

        rv = eventTarget->AddEventListener(NS_LITERAL_STRING("MozSwipeGesture"),
                                           static_cast<nsIDOMEventListener*>(_listener), PR_FALSE);
        NS_ASSERTION(NS_SUCCEEDED(rv), "AddEventListener failed");
        
        rv = eventTarget->AddEventListener(NS_LITERAL_STRING("MozMagnifyGestureStart"),
                                           static_cast<nsIDOMEventListener*>(_listener), PR_FALSE);
        NS_ASSERTION(NS_SUCCEEDED(rv), "AddEventListener failed");
        
        rv = eventTarget->AddEventListener(NS_LITERAL_STRING("MozMagnifyGestureUpdate"),
                                           static_cast<nsIDOMEventListener*>(_listener), PR_FALSE);
        NS_ASSERTION(NS_SUCCEEDED(rv), "AddEventListener failed");

        // Register the CHBrowserListener to listen for Flashblock whitelist
        // and Silverlight blocking checks. Need to use an nsIDOMNSEventTarget
        // since flashblockCheckLoad and silverblockCheckLoad are untrusted.
        nsCOMPtr<nsIDOMNSEventTarget> nsEventTarget = do_QueryInterface(eventTarget);
        if (nsEventTarget) {
          rv = nsEventTarget->AddEventListener(NS_LITERAL_STRING("flashblockCheckLoad"),
                                               static_cast<nsIDOMEventListener*>(_listener),
                                               PR_TRUE, PR_TRUE);
          NS_ASSERTION(NS_SUCCEEDED(rv), "AddEventListener failed: flashblockCheckLoad");

          rv = nsEventTarget->AddEventListener(NS_LITERAL_STRING("silverblockCheckLoad"),
                                               static_cast<nsIDOMEventListener*>(_listener),
                                               PR_TRUE, PR_TRUE);
          NS_ASSERTION(NS_SUCCEEDED(rv), "AddEventListener failed: silverblockCheckLoad");
        }

        rv = eventTarget->AddEventListener(NS_LITERAL_STRING("command"),
                                           static_cast<nsIDOMEventListener*>(_listener), PR_FALSE);
        NS_ASSERTION(NS_SUCCEEDED(rv), "AddEventListener failed");
      }
    }
  }
  return self;
}

- (void)destroyWebBrowser
{
  NS_IF_RELEASE(mPrintSettings);

  { // scope...
    nsCOMPtr<nsIBaseWindow> baseWin = do_QueryInterface(_webBrowser);
    if ( baseWin ) {
      // clean up here rather than in the dtor so that if anyone tries to get our
      // web browser, it won't get a garbage object that's past its prime. As a result,
      // this routine MUST be called otherwise we will leak.
      baseWin->Destroy();
      NS_IF_RELEASE(_webBrowser);
      NS_IF_RELEASE(_listener);
    }
  } // matters

  CHBrowserService::BrowserClosed();
}

- (void)dealloc 
{
  // it is imperative that |destroyWebBrowser()| be called before we get here, otherwise
  // we will leak the webBrowser.
	NS_ASSERTION(!_webBrowser, "BrowserView going away, destroyWebBrowser not called; leaking webBrowser!");
  
#if DEBUG
  NSLog(@"CHBrowserView died.");
#endif

  [super dealloc];
}

- (void)setFrame:(NSRect)frameRect 
{
  [super setFrame:frameRect];
  if (_webBrowser) {
    nsCOMPtr<nsIBaseWindow> window = do_QueryInterface(_webBrowser);
    window->SetSize((PRInt32)frameRect.size.width, 
        (PRInt32)frameRect.size.height,
        PR_TRUE);
  }
}

- (BOOL)isOpaque
{
  return YES;
}

- (void)drawRect:(NSRect)inRect
{
  [[NSColor whiteColor] set];

  const NSRect *rects;
  int numRects;
  [self getRectsBeingDrawn:&rects count:&numRects];

  for (int i = 0; i < numRects; ++i)
    NSRectFill(rects[i]);
}

- (void)addListener:(id <CHBrowserListener>)listener
{
  if ( _listener )
    _listener->AddListener(listener);
}

- (void)removeListener:(id <CHBrowserListener>)listener
{
  if ( _listener )
    _listener->RemoveListener(listener);
}

- (void)setContainer:(NSView<CHBrowserListener, CHBrowserContainer>*)container
{
  if ( _listener )
    _listener->SetContainer(container);
}

// addrefs return value
- (already_AddRefed<nsIDOMWindow>)contentWindow
{
  nsIDOMWindow* window = nsnull;

  if ( _webBrowser )
    _webBrowser->GetContentDOMWindow(&window);

  return window;
}

// addrefs return value
- (already_AddRefed<nsISecureBrowserUI>)secureBrowserUI
{
  nsISecureBrowserUI* secureUI = nsnull;
  
  nsIDocShell* docShell = [self docShell];
  if (docShell)
    docShell->GetSecurityUI(&secureUI);

  return secureUI;
}

- (void)loadURI:(NSString *)urlSpec referrer:(NSString*)referrer flags:(unsigned int)flags allowPopups:(BOOL)inAllowPopups
{
  nsCOMPtr<nsIWebNavigation> nav = do_QueryInterface(_webBrowser);

  // if |inAllowPopups|, temporarily allow popups for the load. We allow them for trusted things like
  // bookmarks.
  nsCOMPtr<nsIDOMWindow> contentWindow = [self contentWindow];
  nsCOMPtr<nsPIDOMWindow> piWindow;
  if (inAllowPopups)
    piWindow = do_QueryInterface(contentWindow);
  nsAutoPopupStatePusher popupStatePusher(piWindow, openAllowed);

  nsAutoString specStr;
  [urlSpec assignTo_nsAString:specStr];

  nsCOMPtr<nsIURI> referrerURI;
  if ( referrer )
    NS_NewURI(getter_AddRefs(referrerURI), [referrer UTF8String]);

  PRUint32 navFlags = nsIWebNavigation::LOAD_FLAGS_NONE;
  if (flags & NSLoadFlagsDontPutInHistory) {
    navFlags |= nsIWebNavigation::LOAD_FLAGS_BYPASS_HISTORY;
  }
  if (flags & NSLoadFlagsReplaceHistoryEntry) {
    navFlags |= nsIWebNavigation::LOAD_FLAGS_REPLACE_HISTORY;
  }
  if (flags & NSLoadFlagsBypassCacheAndProxy) {
    navFlags |= nsIWebNavigation::LOAD_FLAGS_BYPASS_CACHE | 
                nsIWebNavigation::LOAD_FLAGS_BYPASS_PROXY;
  }
  if (flags & NSLoadFlagsAllowThirdPartyFixup) {
    navFlags |= nsIWebNavigation::LOAD_FLAGS_ALLOW_THIRD_PARTY_FIXUP;
  }
  if (flags & NSLoadFlagsBypassClassifier) {
    navFlags |= nsIWebNavigation::LOAD_FLAGS_BYPASS_CLASSIFIER;
  }

  nsresult rv = nav->LoadURI(specStr.get(), navFlags, referrerURI, nsnull, nsnull);
  if (NS_FAILED(rv)) {
    // XXX need to throw
  }
}

- (void)reload:(unsigned int)flags
{
  nsCOMPtr<nsIWebNavigation> nav = do_QueryInterface(_webBrowser);
  if ( !nav )
    return;

  PRUint32 navFlags = nsIWebNavigation::LOAD_FLAGS_NONE;
  if (flags & NSLoadFlagsBypassCacheAndProxy) {
    navFlags |= nsIWebNavigation::LOAD_FLAGS_BYPASS_CACHE | 
                nsIWebNavigation::LOAD_FLAGS_BYPASS_PROXY;
  }
  
  nsresult rv = nav->Reload(navFlags);
  if (NS_FAILED(rv)) {
    // XXX need to throw
  }  
}

- (BOOL)canGoBack
{
  nsCOMPtr<nsIWebNavigation> nav = do_QueryInterface(_webBrowser);
  if ( !nav )
    return NO;

  PRBool can;
  nav->GetCanGoBack(&can);

  return can ? YES : NO;
}

- (BOOL)canGoForward
{
  nsCOMPtr<nsIWebNavigation> nav = do_QueryInterface(_webBrowser);
  if ( !nav )
    return NO;

  PRBool can;
  nav->GetCanGoForward(&can);

  return can ? YES : NO;
}

- (void)goBack
{
  nsCOMPtr<nsIWebNavigation> nav = do_QueryInterface(_webBrowser);
  if ( !nav )
    return;

  nsresult rv = nav->GoBack();
  if (NS_FAILED(rv)) {
    // XXX need to throw
  }  
}

- (void)goForward
{
  nsCOMPtr<nsIWebNavigation> nav = do_QueryInterface(_webBrowser);
  if ( !nav )
    return;

  nsresult rv = nav->GoForward();
  if (NS_FAILED(rv)) {
    // XXX need to throw
  }  
}

- (void)goToSessionHistoryIndex:(int)index
{
  nsCOMPtr<nsIWebNavigation> nav = do_QueryInterface(_webBrowser);
  if ( !nav )
    return;

  nsresult rv = nav->GotoIndex(index);
  if (NS_FAILED(rv)) {
    // XXX need to throw
  }    
}

- (void)stop:(unsigned int)flags
{
  nsCOMPtr<nsIWebNavigation> nav = do_QueryInterface(_webBrowser);
  if ( !nav )
    return;

  PRUint32 stopFlags = 0;
  switch (flags)
  {
    case NSStopLoadNetwork:   stopFlags = nsIWebNavigation::STOP_NETWORK;   break;
    case NSStopLoadContent:   stopFlags = nsIWebNavigation::STOP_CONTENT;   break;
    default:
    case NSStopLoadAll:       stopFlags = nsIWebNavigation::STOP_ALL;       break;
  }
  
  nsresult rv = nav->Stop(stopFlags);
  if (NS_FAILED(rv)) {
    // XXX need to throw
  }    
}

- (void)setProperty:(unsigned int)property toValue:(unsigned int)value
{
	nsCOMPtr<nsIWebBrowserSetup> browserSetup = do_QueryInterface(_webBrowser);
	if (browserSetup)
    browserSetup->SetProperty(property, value);
}

// Gets the current URI in fixed-up form, suitable for display to the user.
// In the case of wyciwyg: URIs, this will not be the actual URI of the page
// according to gecko.
//
// should we be using the window.location URL instead? see nsIDOMLocation.h
- (NSString*)currentURI
{
  nsCOMPtr<nsIWebNavigation> nav = do_QueryInterface(_webBrowser);
  if (!nav)
    return @"";

  nsCOMPtr<nsIURI> uri;
  nav->GetCurrentURI(getter_AddRefs(uri));
  if (!uri)
    return @"";

  nsCAutoString spec;
  nsCOMPtr<nsIURI> exposableURI;
  nsCOMPtr<nsIURIFixup> fixup(do_GetService("@mozilla.org/docshell/urifixup;1"));
  if (fixup && NS_SUCCEEDED(fixup->CreateExposableURI(uri, getter_AddRefs(exposableURI))) && exposableURI)
    exposableURI->GetSpec(spec);
  else
    uri->GetSpec(spec);
  
	return [NSString stringWithUTF8String:spec.get()];
}

- (NSString*)pageLocation
{
  nsCOMPtr<nsIDOMWindow> contentWindow = [self contentWindow];
  NSString* location = [self locationFromDOMWindow:contentWindow];
  return location ? location : @"";
}

- (NSString*)pageLocationHost
{
  nsCOMPtr<nsIDOMWindow> domWindow = [self contentWindow];
  if (!domWindow) return @"";
  nsCOMPtr<nsIDOMDocument> domDocument;
  domWindow->GetDocument(getter_AddRefs(domDocument));
  if (!domDocument) return @"";
  nsCOMPtr<nsIDOMNSDocument> nsDoc(do_QueryInterface(domDocument));
  if (!nsDoc) return @"";

  nsCOMPtr<nsIDOMLocation> location;
  nsDoc->GetLocation(getter_AddRefs(location));
  if (!location) return @"";
  nsAutoString hostStr;
  location->GetHost(hostStr);

  return [NSString stringWith_nsAString:hostStr];
}

- (NSString*)pageTitle
{
  nsCOMPtr<nsIDOMWindow> window = [self contentWindow];
  if (!window)
    return @"";
  
  nsCOMPtr<nsIDOMDocument> htmlDoc;
  window->GetDocument(getter_AddRefs(htmlDoc));

  nsCOMPtr<nsIDOMHTMLDocument> htmlDocument(do_QueryInterface(htmlDoc));
  if (!htmlDocument)
    return @"";

  nsAutoString titleString;
  htmlDocument->GetTitle(titleString);
  return [NSString stringWith_nsAString:titleString];
}

- (NSDate*)pageLastModifiedDate
{
  nsCOMPtr<nsIDOMWindow> domWindow = [self contentWindow];
  if (!domWindow)
    return nil;

  nsCOMPtr<nsIDOMDocument> domDocument;
  domWindow->GetDocument(getter_AddRefs(domDocument));
  if (!domDocument)
    return nil;
  nsCOMPtr<nsIDOMNSDocument> nsDoc(do_QueryInterface(domDocument));
  if (!nsDoc)
    return nil;

  nsAutoString lastModifiedDate;
  nsDoc->GetLastModified(lastModifiedDate);

  // sucks that we have to parse this back to a PRTime, thence back
  // again to an NSDate. Why doesn't nsIDOMNSDocument have an accessor
  // which can give me a date directly?
  PRTime time;
  PRStatus st = PR_ParseTimeString(NS_ConvertUTF16toUTF8(lastModifiedDate).get(), PR_FALSE /* local time */, &time);
  if (st == PR_SUCCESS)
    return [NSDate dateWithPRTime:time];

  return nil;
}

- (CHBrowserListener*)cocoaBrowserListener
{
  return _listener;
}

- (nsIWebBrowser*)webBrowser
{
  NS_IF_ADDREF(_webBrowser);
  return _webBrowser;
}

- (void)setWebBrowser:(nsIWebBrowser*)browser
{
  NS_IF_ADDREF(browser);				// prevents destroying |browser| if |browser| == |_webBrowser|
  NS_IF_RELEASE(_webBrowser);
  _webBrowser = browser;

  if (_webBrowser) {
    // Set the container nsIWebBrowserChrome
    _webBrowser->SetContainerWindow(static_cast<nsIWebBrowserChrome *>(_listener));

    NSRect frame = [self frame];
 
    // Hook up the widget hierarchy with us as the parent
    nsCOMPtr<nsIBaseWindow> baseWin = do_QueryInterface(_webBrowser);
    baseWin->InitWindow((NSView*)self, nsnull, 0, 0, (int)frame.size.width, (int)frame.size.height);
    baseWin->Create();
  }

}

// Returns the currently focused DOM element, AddRef'd.
- (already_AddRefed<nsIDOMElement>)focusedDOMElement
{
  nsresult rv;
  nsCOMPtr<nsIFocusManager> fm =
    do_GetService("@mozilla.org/focus-manager;1", &rv);
  NS_ENSURE_SUCCESS(rv, nsnull);
  NS_ENSURE_TRUE(fm, nsnull);

  nsCOMPtr<nsIDOMElement> focusedElement;
  fm->GetFocusedElement(getter_AddRefs(focusedElement));
  if (!focusedElement)
    return nsnull;

  nsIDOMElement* domElement = focusedElement.get();
  NS_IF_ADDREF(domElement);
  return domElement;
}

- (NSImage*)snapshot
{
  NSSize viewportSize = [self bounds].size;
  // We don't draw scrollbars, so set the snapshot width to be the smaller of
  // the view width and the dom width to prevent a blank strip in the snapshot.
  nsCOMPtr<nsIDOMWindow> domWindow = [self contentWindow];
  if (!domWindow)
    return nil;
  // GetIntrinsicSize can fail, in which case pageWidth and pageHeight aren't
  // set; if the values remain 0, we'll fall back to the viewport below.
  int pageWidth = 0;
  int pageHeight = 0;
  GeckoUtils::GetIntrinsicSize(domWindow, &pageWidth, &pageHeight);
  // Enforce a non-zero size, since Gecko gets very angry with a zero-sized
  // Quartz surface.
  if (pageWidth == 0)
    pageWidth = viewportSize.width;
  if (pageHeight == 0)
    pageHeight = viewportSize.height;
  NSSize snapshotSize = NSMakeSize(MIN(pageWidth, viewportSize.width),
                                   viewportSize.height);

  // Create a context to draw into.
  nsRefPtr<gfxQuartzSurface> surface = new gfxQuartzSurface(gfxSize(snapshotSize.width,
                                                                    snapshotSize.height),
                                                            gfxQuartzSurface::ImageFormatARGB32);

  if (!surface)
    return nil;
  nsRefPtr<gfxContext> context = new gfxContext(surface);
  if (!context)
    return nil;

  // Get the page presentation.
  nsCOMPtr<nsIDocShell> docShell = [self docShell];
  if (!docShell)
    return nil;
  nsCOMPtr<nsPresContext> presContext;
  docShell->GetPresContext(getter_AddRefs(presContext));
  if (!presContext)
    return nil;
  nsIPresShell* presShell = presContext->PresShell();
  if (!presShell)
    return nil;

  // Draw the desired section of the page into our context.
  PRInt32 scrollX, scrollY;
  domWindow->GetScrollX(&scrollX);
  domWindow->GetScrollY(&scrollY);
  PRInt32 appUnitsPerPixel = presContext->AppUnitsPerDevPixel();
  nsRect viewRect(NSIntPixelsToAppUnits(scrollX, appUnitsPerPixel),
                  NSIntPixelsToAppUnits(scrollY, appUnitsPerPixel),
                  NSIntPixelsToAppUnits(viewportSize.width, appUnitsPerPixel),
                  NSIntPixelsToAppUnits(viewportSize.height, appUnitsPerPixel));
  presShell->RenderDocument(viewRect,
                            nsIPresShell::RENDER_IGNORE_VIEWPORT_SCROLLING,
                            NS_RGB(255, 255, 255),
                            context);

  // Now transfer the context contents into an NSImage.
  CGContextRef surfaceContext = surface->GetCGContext();
  if (!surfaceContext)
    return nil;
  CGImageRef cgImage = CGBitmapContextCreateImage(surfaceContext);
  NSImage* snapshot = [[[NSImage alloc] initWithSize:snapshotSize] autorelease];
  NSRect imageRect = NSMakeRect(0, 0, snapshotSize.width, snapshotSize.height);
  [snapshot lockFocus];
  CGContextDrawImage((CGContextRef)[[NSGraphicsContext currentContext] graphicsPort],
                     *(CGRect*)&imageRect, cgImage);
  [snapshot unlockFocus];
  CGImageRelease(cgImage);
  
  return snapshot;
}

-(void) saveInternal: (nsIURI*)aURI
        withDocument: (nsIDOMDocument*)aDocument
        suggestedFilename: (NSString*)aFileName
        bypassCache: (BOOL)aBypassCache
        filterView: (NSView*)aFilterView
{
    // Create our web browser persist object.  This is the object that knows
    // how to actually perform the saving of the page (and of the images
    // on the page).
    nsCOMPtr<nsIWebBrowserPersist> webPersist(do_CreateInstance(kPersistContractID));
    if (!webPersist)
        return;
    
    // Make a temporary file object that we can save to.
    nsCOMPtr<nsIProperties> dirService(do_GetService(kDirServiceContractID));
    if (!dirService)
        return;
    nsCOMPtr<nsIFile> tmpFile;
    dirService->Get("TmpD", NS_GET_IID(nsIFile), getter_AddRefs(tmpFile));
    static short unsigned int tmpRandom = 0;
    nsAutoString tmpNo; tmpNo.AppendInt(tmpRandom++);
    nsAutoString saveFile(NS_LITERAL_STRING("-sav"));
    saveFile += tmpNo;
    saveFile += NS_LITERAL_STRING("tmp");
    tmpFile->Append(saveFile); 
    
    // Get the post data if we're an HTML doc.
    nsCOMPtr<nsIInputStream> postData;
    if (aDocument) {
      nsCOMPtr<nsIWebNavigation> webNav(do_QueryInterface(_webBrowser));
      if (webNav) {
        nsCOMPtr<nsISHistory> sessionHistory;
        webNav->GetSessionHistory(getter_AddRefs(sessionHistory));
        nsCOMPtr<nsIHistoryEntry> entry;
        PRInt32 sindex;
        sessionHistory->GetIndex(&sindex);
        sessionHistory->GetEntryAtIndex(sindex, PR_FALSE, getter_AddRefs(entry));
        nsCOMPtr<nsISHEntry> shEntry(do_QueryInterface(entry));
        if (shEntry)
            shEntry->GetPostData(getter_AddRefs(postData));
      }
    }

    // when saving, we first fire off a save with a nsHeaderSniffer as a progress
    // listener. This allows us to look for the content-disposition header, which
    // can supply a filename, and maybe has something to do with CGI-generated
    // content (?)
    nsAutoString fileName;
    [aFileName assignTo_nsAString:fileName];
    nsHeaderSniffer* sniffer = new nsHeaderSniffer(webPersist, tmpFile, aURI, 
                                                   aDocument, postData, fileName, aBypassCache,
                                                   aFilterView);
    if (!sniffer)
        return;
    webPersist->SetProgressListener(sniffer);  // owned
    webPersist->SaveURI(aURI, nsnull, nsnull, nsnull, nsnull, tmpFile);
}

-(void)printDocument
{
  if (!_webBrowser)
    return;

  [self ensurePrintSettings];

  nsCOMPtr<nsIDOMWindow> domWindow;
  _webBrowser->GetContentDOMWindow(getter_AddRefs(domWindow));
  nsCOMPtr<nsIInterfaceRequestor> ir(do_QueryInterface(domWindow));
  nsCOMPtr<nsIWebBrowserPrint> print;
  ir->GetInterface(NS_GET_IID(nsIWebBrowserPrint), getter_AddRefs(print));
  print->Print(mPrintSettings, nsnull);

  [self savePrintSettings];
}

-(void)pageSetup
{
  if (!_webBrowser)
    return;
  nsCOMPtr<nsIDOMWindow> domWindow;
  _webBrowser->GetContentDOMWindow(getter_AddRefs(domWindow));

  nsCOMPtr<nsIPrintingPromptService> ppService =
      do_GetService("@mozilla.org/embedcomp/printingprompt-service;1");
  if (!ppService)
    return;
  [self ensurePrintSettings];
  if (NS_SUCCEEDED(ppService->ShowPageSetup(domWindow, mPrintSettings, nsnull)))
    [self savePrintSettings];
}

- (void)ensurePrintSettings
{
  NS_IF_RELEASE(mPrintSettings);
  nsCOMPtr<nsIPrintSettingsService> psService =
      do_GetService("@mozilla.org/gfx/printsettings-service;1");
  if (!psService)
    return;

  if (mUseGlobalPrintSettings)
    psService->GetGlobalPrintSettings(&mPrintSettings);
  else
    psService->GetNewPrintSettings(&mPrintSettings);

  if (mPrintSettings && mUseGlobalPrintSettings)
    psService->InitPrintSettingsFromPrefs(mPrintSettings, PR_FALSE,
                                          nsIPrintSettings::kInitSaveAll);
}

- (void)savePrintSettings
{
  if (mPrintSettings && mUseGlobalPrintSettings) {
    nsCOMPtr<nsIPrintSettingsService> psService =
        do_GetService("@mozilla.org/gfx/printsettings-service;1");
    if (psService)
      psService->SavePrintSettingsToPrefs(mPrintSettings, PR_FALSE,
                                          nsIPrintSettings::kInitSaveAll);
  }
}

//
// -findActions:
//
// Called on the first responder when the user executes one of the find commands. The
// tag is the action to perform.
//
- (IBAction)findActions:(id)inSender
{
  switch ([inSender tag]) {
    case NSFindPanelActionSetFindString:
    {
      // set the selected text on the find pasteboard so it's usable from other apps
      NSString* selectedText = [self selectedText];
      NSPasteboard* pboard = [NSPasteboard pasteboardWithName:NSFindPboard];
      [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
      [pboard setString:selectedText forType:NSStringPboardType];
      
      // set gecko's search string
      nsCOMPtr<nsIWebBrowserFind> webFind = do_GetInterface(_webBrowser);
      if (webFind) {
        nsAutoString sel;
        [selectedText assignTo_nsAString:sel];
        webFind->SetSearchString(sel.get()); 
      }
      break;
    }
    
    case NSFindPanelActionNext:
      [self findInPage:NO];
      break;
    
    case NSFindPanelActionPrevious:
      [self findInPage:YES];
      break;
  }
}

- (void)collapseSelection
{
  nsCOMPtr<nsIDOMWindow> domWindow = [self focussedDOMWindow];
  if (domWindow) {
    nsCOMPtr<nsISelection> selection;
    domWindow->GetSelection(getter_AddRefs(selection));
    if (selection)
      selection->CollapseToStart();
  }
}

- (BOOL)findInPageWithPattern:(NSString*)inText caseSensitive:(BOOL)inCaseSensitive
    wrap:(BOOL)inWrap backwards:(BOOL)inBackwards
{
    if (!_webBrowser)
      return NO;
    PRBool found =  PR_FALSE;
    
    nsCOMPtr<nsIWebBrowserFocus> wbf(do_QueryInterface(_webBrowser));
    nsCOMPtr<nsIDOMWindow> rootWindow;
    nsCOMPtr<nsIDOMWindow> focusedWindow;
    _webBrowser->GetContentDOMWindow(getter_AddRefs(rootWindow));
    wbf->GetFocusedWindow(getter_AddRefs(focusedWindow));
    if (!focusedWindow)
        focusedWindow = rootWindow;
    nsCOMPtr<nsIWebBrowserFind> webFind(do_GetInterface(_webBrowser));
    if ( webFind ) {
      nsCOMPtr<nsIWebBrowserFindInFrames> framesFind(do_QueryInterface(webFind));
      framesFind->SetRootSearchFrame(rootWindow);
      framesFind->SetCurrentSearchFrame(focusedWindow);

      // If case sensitivity has been toggled, collapse the selection before
      // searching (see the comment in findInPage:).
      PRBool inCaseSensitivePRBool = inCaseSensitive ? PR_TRUE : PR_FALSE;
      PRBool wasCaseSensitivePRBool;
      webFind->GetMatchCase(&wasCaseSensitivePRBool);
      if (inCaseSensitivePRBool != wasCaseSensitivePRBool)
        [self collapseSelection];

      webFind->SetMatchCase(inCaseSensitivePRBool);
      webFind->SetWrapFind(inWrap ? PR_TRUE : PR_FALSE);
    
      nsAutoString findString;
      [inText assignTo_nsAString:findString];
      webFind->SetSearchString(findString.get());

      return [self findInPage:inBackwards];
    }
    return found;
}

- (BOOL)findInPage:(BOOL)inBackwards
{
  nsCOMPtr<nsIWebBrowserFind> webFind = do_GetInterface(_webBrowser);
  if (!webFind)
    return NO;

  // nsIWebBrowserFind searches starting at the *end* of the current selection,
  // which gives very unexpected results when doing live searching. To work
  // around that, if the search string and the current selection aren't the same
  // (which would indicate a find next/previous), collapse the selection before
  // searching.
  nsAutoString findString;
  webFind->GetSearchString(getter_Copies(findString));
  NSString* searchText = [NSString stringWith_nsAString:findString];
  NSString* selectedText = [self selectedText];
  if (![searchText caseInsensitiveCompare:selectedText] == NSOrderedSame)
    [self collapseSelection];

  webFind->SetFindBackwards(inBackwards);

  PRBool found;
  webFind->FindNext(&found);

  [self postFindStatusNotification:(BOOL)found];
  return (BOOL)found;
}

- (void)postFindStatusNotification:(BOOL)success
{
  NSDictionary* successInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:success]
                                                          forKey:kFindStatusNotificationSuccessKey];
  NSNotification* note = [NSNotification notificationWithName:kFindStatusNotification
                                                       object:self
                                                     userInfo:successInfo];
  [[NSNotificationCenter defaultCenter] postNotification:note];
}

- (NSString*)lastFindText
{
  nsCOMPtr<nsIWebBrowserFind> webFind = do_GetInterface(_webBrowser);
  if (!webFind)
    return nil;

  nsAutoString searchString;
  webFind->GetSearchString(getter_Copies(searchString));
  return [NSString stringWith_nsAString:PromiseFlatString(searchString)];
}

- (void)saveURL: (NSView*)aFilterView url: (NSString*)aURLSpec suggestedFilename: (NSString*)aFilename
{
  nsCOMPtr<nsIURI> url;
  nsresult rv = NS_NewURI(getter_AddRefs(url), [aURLSpec UTF8String]);
  if (NS_FAILED(rv))
    return;
  
  [self saveInternal: url.get()
        withDocument: nsnull
   suggestedFilename: aFilename
         bypassCache: YES
          filterView: aFilterView];
}

- (already_AddRefed<nsIDOMWindow>)focussedDOMWindow
{
  if (!_webBrowser)
    return nsnull;

  nsCOMPtr<nsIWebBrowserFocus> wbf(do_QueryInterface(_webBrowser));
  nsIDOMWindow* domWindow;
  wbf->GetFocusedWindow(&domWindow);
  if (!domWindow)
    _webBrowser->GetContentDOMWindow(&domWindow);
  return domWindow;
}

- (NSString*)locationFromDOMWindow:(nsIDOMWindow*)inDOMWindow
{
  if (!inDOMWindow)
    return nil;
  nsCOMPtr<nsIDOMDocument> domDocument;
  inDOMWindow->GetDocument(getter_AddRefs(domDocument));
  if (!domDocument)
    return nil;
  nsAutoString urlStr;
  if (!GeckoUtils::GetURIForDocument(domDocument, urlStr))
    return nil;
  return [NSString stringWith_nsAString:urlStr];
}

-(NSString*)focusedURLString
{
  if (!_webBrowser)
    return @"";

  nsCOMPtr<nsIDOMWindow> focussedWindow = [self focussedDOMWindow];
  NSString* locationString = [self locationFromDOMWindow:focussedWindow];
  return locationString ? locationString : @"";
}

- (void)saveDocument:(BOOL)focusedFrame filterView:(NSView*)aFilterView
{
  if (!_webBrowser)
    return;
  
  nsCOMPtr<nsIDOMWindow> domWindow;
  if (focusedFrame)
    domWindow = [self focussedDOMWindow];
  else
    _webBrowser->GetContentDOMWindow(getter_AddRefs(domWindow));
  if (!domWindow)
      return;
  
  nsCOMPtr<nsIDOMDocument> domDocument;
  domWindow->GetDocument(getter_AddRefs(domDocument));
  if (!domDocument)
      return;

  NSString* windowLocation = [self locationFromDOMWindow:domWindow];

  nsCOMPtr<nsIURI> url;
  nsresult rv = NS_NewURI(getter_AddRefs(url), [windowLocation UTF8String]);
  if (NS_FAILED(rv))
      return;
  
  [self saveInternal:url.get()
        withDocument:domDocument
   suggestedFilename:@""
         bypassCache:NO
          filterView:aFilterView];
}

-(void)doCommand:(const char*)commandName
{
  nsCOMPtr<nsICommandManager> commandMgr(do_GetInterface(_webBrowser));
  if (commandMgr) {
    nsresult rv;
    rv = commandMgr->DoCommand(commandName, nsnull, nsnull);
#if DEBUG
    if (NS_FAILED(rv))
      NSLog(@"DoCommand failed");
#endif
  }
  else {
#if DEBUG
    NSLog(@"No command manager");
#endif
  }
}

-(BOOL)isCommandEnabled:(const char*)commandName
{
  PRBool	isEnabled = PR_FALSE;
  nsCOMPtr<nsICommandManager> commandMgr(do_GetInterface(_webBrowser));
  if (commandMgr) {
    nsresult rv;
    rv = commandMgr->IsCommandEnabled(commandName, nsnull, &isEnabled);
#if DEBUG
    if (NS_FAILED(rv))
      NSLog(@"IsCommandEnabled failed");
#endif
  }
  else {
#if DEBUG
    NSLog(@"No command manager");
#endif
  }
  return (isEnabled) ? YES : NO;
}

- (BOOL)isTextBasedContent
{
  nsCOMPtr<nsIDOMWindow> domWindow = [self contentWindow];
  if (!domWindow)
    return NO;

  nsCOMPtr<nsIDOMDocument> domDocument;
  domWindow->GetDocument(getter_AddRefs(domDocument));
  if (!domDocument)
    return NO;
  
  nsCOMPtr<nsIDOMNSDocument> nsDoc(do_QueryInterface(domDocument));
  if (!nsDoc)
    return NO;
  
  nsAutoString contentType;
  nsDoc->GetContentType(contentType);
  
  NSString* mimeType = [NSString stringWith_nsAString:contentType];
  if ([mimeType hasPrefix:@"text/"] ||
      ([mimeType hasSuffix:@"+xml"] && 
      ![mimeType isEqualToString:@"application/vnd.mozilla.xul+xml"]) ||
      [mimeType isEqualToString:@"application/x-javascript"] ||
      [mimeType isEqualToString:@"application/javascript"] ||
      [mimeType isEqualToString:@"application/ecmascript"] ||
      [mimeType isEqualToString:@"application/xml"])
  {
    return YES;
  }
  
  return NO;
}

- (BOOL)isImageBasedContent
{
  nsCOMPtr<nsIDOMWindow> domWindow = [self contentWindow];
  if (!domWindow)
    return NO;

  nsCOMPtr<nsIDOMDocument> domDocument;
  domWindow->GetDocument(getter_AddRefs(domDocument));
  if (!domDocument)
    return NO;
  
  nsCOMPtr<nsIDOMNSDocument> nsDoc(do_QueryInterface(domDocument));
  if (!nsDoc)
    return NO;
  
  nsAutoString contentType;
  nsDoc->GetContentType(contentType);
  
  NSString* mimeType = [NSString stringWith_nsAString:contentType];
  return [mimeType hasPrefix:@"image/"];
}

-(IBAction)cut:(id)aSender
{
  nsCOMPtr<nsIClipboardCommands> clipboard(do_GetInterface(_webBrowser));
  if ( clipboard )
    clipboard->CutSelection();
}

-(BOOL)canCut
{
  PRBool canCut = PR_FALSE;
  nsCOMPtr<nsIClipboardCommands> clipboard(do_GetInterface(_webBrowser));
  if ( clipboard )
    clipboard->CanCutSelection(&canCut);
  // Core considers password field text copyable, so check it ourselves
  return canCut && ![self isPasswordFieldFocused];
}

-(IBAction)copy:(id)aSender
{
  nsCOMPtr<nsIClipboardCommands> clipboard(do_GetInterface(_webBrowser));
  if ( clipboard )
    clipboard->CopySelection();
}

-(BOOL)canCopy
{
  PRBool canCopy = PR_FALSE;
  nsCOMPtr<nsIClipboardCommands> clipboard(do_GetInterface(_webBrowser));
  if ( clipboard )
    clipboard->CanCopySelection(&canCopy);
  // Core considers password field text copyable, so check it ourselves
  return canCopy && ![self isPasswordFieldFocused];
}

-(IBAction)paste:(id)aSender
{
  nsCOMPtr<nsIClipboardCommands> clipboard(do_GetInterface(_webBrowser));
  if ( clipboard )
    clipboard->Paste();
}

-(BOOL)canPaste
{
  PRBool canCut = PR_FALSE;
  nsCOMPtr<nsIClipboardCommands> clipboard(do_GetInterface(_webBrowser));
  if ( clipboard )
    clipboard->CanPaste(&canCut);
  return canCut;
}

-(IBAction)delete:(id)aSender
{
  [self doCommand: "cmd_delete"];
}

-(BOOL)canDelete
{
  return [self isCommandEnabled: "cmd_delete"];
}

-(IBAction)selectAll:(id)aSender
{
  nsCOMPtr<nsIClipboardCommands> clipboard(do_GetInterface(_webBrowser));
  if ( clipboard )
    clipboard->SelectAll();
}

-(IBAction)undo:(id)aSender
{
  [self doCommand: "cmd_undo"];
}

-(IBAction)redo:(id)aSender
{
  [self doCommand: "cmd_redo"];
}

- (BOOL)canUndo
{
  return [self isCommandEnabled: "cmd_undo"];
}

- (BOOL)canRedo
{
  return [self isCommandEnabled: "cmd_redo"];
}

- (void)makeTextBigger
{
  [self incrementTextZoom:0.25 min:MIN_TEXT_ZOOM max:MAX_TEXT_ZOOM];
}

- (void)makeTextSmaller
{
  [self incrementTextZoom:-0.25 min:MIN_TEXT_ZOOM max:MAX_TEXT_ZOOM];
}

- (void)makeTextDefaultSize
{
  nsCOMPtr<nsIContentViewer> contentViewer = dont_AddRef([self contentViewer]);
  nsCOMPtr<nsIMarkupDocumentViewer> markupViewer(do_QueryInterface(contentViewer));
  if (!markupViewer)
    return;

  markupViewer->SetTextZoom(DEFAULT_TEXT_ZOOM);
}

- (BOOL)canMakeTextBigger
{
  float zoom = [self textZoom];
  return zoom < MAX_TEXT_ZOOM;
}

- (BOOL)canMakeTextSmaller
{
  float zoom = [self textZoom];
  return zoom > MIN_TEXT_ZOOM;
}

- (BOOL)isTextDefaultSize
{
  return (fabsf([self textZoom] - DEFAULT_TEXT_ZOOM) < .001);
}

- (void)makePageBigger
{
  [self incrementPageZoom:PAGE_ZOOM_INCREMENT min:MIN_PAGE_ZOOM max:MAX_PAGE_ZOOM];
}

- (void)makePageSmaller
{
  [self incrementPageZoom:-PAGE_ZOOM_INCREMENT min:MIN_PAGE_ZOOM max:MAX_PAGE_ZOOM];
}

- (void)makePageDefaultSize
{
  nsCOMPtr<nsIContentViewer> contentViewer = dont_AddRef([self contentViewer]);
  nsCOMPtr<nsIMarkupDocumentViewer> markupViewer(do_QueryInterface(contentViewer));
  if (!markupViewer)
    return;
  
  markupViewer->SetFullZoom(DEFAULT_PAGE_ZOOM);
}

- (BOOL)canMakePageBigger
{
  return [self pageZoom] < MAX_PAGE_ZOOM;
}

- (BOOL)canMakePageSmaller
{
  return [self pageZoom] > MIN_PAGE_ZOOM;
}

- (BOOL)isPageDefaultSize
{
  return (fabsf([self pageZoom] - DEFAULT_PAGE_ZOOM) < .001);
}

- (void)pageUp
{
  [self doCommand:"cmd_scrollPageUp"];
}

- (void)pageDown
{
  [self doCommand:"cmd_scrollPageDown"];
}

- (BOOL)shouldUnload
{
  nsCOMPtr<nsIContentViewer> contentViewer = dont_AddRef([self contentViewer]);
  if (!contentViewer)
    return YES;

  PRBool canUnload;
  contentViewer->PermitUnload(PR_TRUE, &canUnload);
  return canUnload ? YES : NO;
}

// -isPasswordFieldFocused
//
// Returs YES if a password field in the content area has focus.
// We need this only because core believes that password fields are
// valid cut/copy targets (see bug 217729).
//
- (BOOL)isPasswordFieldFocused
{
  BOOL isFocused = NO;

  nsCOMPtr<nsIDOMElement> focusedItem = [self focusedDOMElement];

  nsCOMPtr<nsIDOMHTMLInputElement> input = do_QueryInterface(focusedItem);
  if (input) {
    nsAutoString type;
    input->GetType(type);
    if (type.Equals(NS_LITERAL_STRING("password")))
      isFocused = YES;
  }

  return isFocused;
}

// -isTextFieldFocused
//
// Determine if a text field in the content area has focus. Returns YES if the
// focus is in a <input type="text">, input type="password", or <textarea>
//
- (BOOL)isTextFieldFocused
{
  nsCOMPtr<nsIDOMElement> focusedItem = [self focusedDOMElement];
  
  // we got it, now check if it's what we care about
  nsCOMPtr<nsIDOMHTMLInputElement> input = do_QueryInterface(focusedItem);
  nsCOMPtr<nsIDOMHTMLTextAreaElement> textArea = do_QueryInterface(focusedItem);
  if (input) {
    nsAutoString type;
    input->GetType(type);
    if (type == NS_LITERAL_STRING("text"))
      return YES;
    if (type == NS_LITERAL_STRING("password"))
      return YES;
  }
  else if (textArea) {
    return YES;
  }
  else { // check for Midas
    nsresult rv;
    nsCOMPtr<nsIFocusManager> fm =
      do_GetService("@mozilla.org/focus-manager;1", &rv);
    NS_ENSURE_SUCCESS(rv, NO);
    NS_ENSURE_TRUE(fm, NO);

    nsCOMPtr<nsIDOMWindow> focusedWindow;
    fm->GetFocusedWindow(getter_AddRefs(focusedWindow));
    NS_ENSURE_TRUE(focusedWindow, NO);

    nsCOMPtr<nsIDOMDocument> domDoc;
    rv = focusedWindow->GetDocument(getter_AddRefs(domDoc));
    NS_ENSURE_SUCCESS(rv, NO);

    nsCOMPtr<nsIDOMNSHTMLDocument> htmlDoc = do_QueryInterface(domDoc, &rv);
    NS_ENSURE_SUCCESS(rv, NO);
    NS_ENSURE_TRUE(htmlDoc, NO);

    nsAutoString designMode;
    htmlDoc->GetDesignMode(designMode);
    if (designMode.EqualsLiteral("on"))
      return YES;
  }

  return NO;
}

// -isPluginFocused
//
// Determine if a plugin/applet in the content area has focus. Returns YES if the
// focus is in a <embed>, <object>, or <applet>
//
- (BOOL)isPluginFocused
{
  nsCOMPtr<nsIDOMElement> focusedItem = [self focusedDOMElement];
  
  // we got it, now check if it's what we care about
  nsCOMPtr<nsIDOMHTMLEmbedElement> embed = do_QueryInterface(focusedItem);
  nsCOMPtr<nsIDOMHTMLObjectElement> object = do_QueryInterface(focusedItem);
  nsCOMPtr<nsIDOMHTMLAppletElement> applet = do_QueryInterface(focusedItem);
  return (embed || object || applet);
}

- (void)moveToBeginningOfDocument:(id)sender
{
  [self doCommand: "cmd_moveTop"];
}

- (void)moveToEndOfDocument:(id)sender
{
  [self doCommand: "cmd_moveBottom"];
}

- (void)moveToBeginningOfDocumentAndModifySelection:(id)sender
{
  [self doCommand: "cmd_selectTop"];
}

- (void)moveToEndOfDocumentAndModifySelection:(id)sender
{
  [self doCommand: "cmd_selectBottom"];
}

- (void)doBeforePromptDisplay
{
  [[self browserContainer] willShowPrompt];
}

- (void)doAfterPromptDismissal
{
  [[self browserContainer] didDismissPrompt];
}

- (BOOL)setActive:(BOOL)aIsActive
{
  nsCOMPtr<nsIWebBrowserFocus> wbf(do_QueryInterface(_webBrowser));
  if (wbf) {
    if (aIsActive) {
      // If presShell is NULL, core will get into a broken focus state, so
      // defer the call until we have loaded something.
      nsCOMPtr<nsIDocShell> docShell = [self docShell];
      nsCOMPtr<nsIPresShell> presShell;
      if (docShell)
        docShell->GetPresShell(getter_AddRefs(presShell));
      if (!presShell)
        return NO;

      wbf->Activate();
    } else {
      wbf->Deactivate();
    }
  }
  return YES;
}

-(NSMenu*)contextMenu
{
	return [[self browserContainer] contextMenu];
}

-(NSWindow*)nativeWindow
{
  NSWindow* window = [self window];
  if (window)
    return window; // We're visible.  Just hand the window back.

  // We're invisible.  It's likely that we're in a Cocoa tab view.
  // First see if we have a cached window.
  if (mWindow)
    return mWindow;
  
  // Finally, see if our parent responds to the nativeWindow selector,
  // and if they do, let them handle it.
  return [[self browserContainer] nativeWindow];
}

// does NOT addref return value
- (nsIDocShell*)docShell
{
  if (!_webBrowser)
    return NULL;
  nsCOMPtr<nsIDOMWindow> domWindow;
  _webBrowser->GetContentDOMWindow(getter_AddRefs(domWindow));
  nsCOMPtr<nsPIDOMWindow> privWin(do_QueryInterface(domWindow));
  if (!privWin)
    return NULL;
  return privWin->GetDocShell();
}

- (id<CHBrowserContainer>)browserContainer
{
  // i'm not sure why this doesn't return whatever -setContainer: was called with
  if ([[self superview] conformsToProtocol:@protocol(CHBrowserContainer)])
    return (id<CHBrowserContainer>)[self superview];

  return nil;
}

- (nsIContentViewer*)contentViewer		// addrefs return value
{
  nsIDocShell* docShell = [self docShell];
  nsIContentViewer* cv = NULL;
  if (docShell)
    docShell->GetContentViewer(&cv);		// addrefs
  return cv;
}

- (float)textZoom
{
  nsCOMPtr<nsIContentViewer> contentViewer = dont_AddRef([self contentViewer]);
  nsCOMPtr<nsIMarkupDocumentViewer> markupViewer(do_QueryInterface(contentViewer));
  if (!markupViewer)
    return DEFAULT_TEXT_ZOOM;

  float zoom;
  markupViewer->GetTextZoom(&zoom);
  return zoom;
}

- (void)incrementTextZoom:(float)increment min:(float)min max:(float)max
{
  nsCOMPtr<nsIContentViewer> contentViewer = dont_AddRef([self contentViewer]);
  nsCOMPtr<nsIMarkupDocumentViewer> markupViewer(do_QueryInterface(contentViewer));
  if (!markupViewer)
    return;

  float zoom;
  markupViewer->GetTextZoom(&zoom);
  zoom += increment;
  
  if (zoom < min)
    zoom = min;

  if (zoom > max)
    zoom = max;

  markupViewer->SetTextZoom(zoom);
}

- (float)pageZoom
{
  nsCOMPtr<nsIContentViewer> contentViewer = dont_AddRef([self contentViewer]);
  nsCOMPtr<nsIMarkupDocumentViewer> markupViewer(do_QueryInterface(contentViewer));
  if (!markupViewer)
    return DEFAULT_PAGE_ZOOM;
  
  float zoom;
  markupViewer->GetFullZoom(&zoom);
  return zoom;
}

- (void)incrementPageZoom:(float)increment min:(float)min max:(float)max
{
  nsCOMPtr<nsIContentViewer> contentViewer = dont_AddRef([self contentViewer]);
  nsCOMPtr<nsIMarkupDocumentViewer> markupViewer(do_QueryInterface(contentViewer));
  if (!markupViewer)
    return;
  
  float zoom;
  markupViewer->GetFullZoom(&zoom);
  zoom += increment;
  
  if (zoom < min)
    zoom = min;
  
  if (zoom > max)
    zoom = max;
  
  markupViewer->SetFullZoom(zoom);
}

#pragma mark -

-(BOOL)validateMenuItem: (NSMenuItem*)aMenuItem
{
  // Window actions are disabled while a sheet is showing
  if ([[self window] attachedSheet])
    return NO;

  // update first responder items based on the selection
  SEL action = [aMenuItem action];
  if (action == @selector(cut:))
    return [self canCut];    
  else if (action == @selector(copy:))
    return [self canCopy];
  else if (action == @selector(paste:))
    return [self canPaste];
  else if (action == @selector(delete:))
    return [self canDelete];
  else if (action == @selector(undo:))
    return [self canUndo];
  else if (action == @selector(redo:))
    return [self canRedo];
  else if (action == @selector(selectAll:))
    return YES;
  else if (action == @selector(findActions:)) {
    if (![self isTextBasedContent])
      return NO;
    long tag = [aMenuItem tag];
    if (tag == NSFindPanelActionNext || tag == NSFindPanelActionPrevious)
      return ([[self lastFindText] length] > 0);
    return YES;
  }
  
  return NO;
}

#pragma mark -

// ******** services support *************** //

// this needs to be efficient.
// if sendType is nil, the service doesn't require input from us.
// if returnType is nil, the service doesn't return data
- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
  if (sendType && returnType)
  {
    // service needs to both get and put data
    if (([sendType isEqual:NSStringPboardType] && [self isCommandEnabled:"cmd_getContents"]) &&
        ([returnType isEqual:NSStringPboardType] && [self isCommandEnabled:"cmd_insertText"]))
      return self;
  }
  else if (sendType)
  {
    if ([sendType isEqual:NSStringPboardType] && [self isCommandEnabled:"cmd_getContents"])
      return self;
  }
  else if (returnType)
  {
    if ([returnType isEqual:NSStringPboardType] && [self isCommandEnabled:"cmd_insertText"])
      return self;
  }

  return [super validRequestorForSendType:sendType returnType:returnType];
}

//
// -selectedText
//
// Returns the currently selected text as an NSString. 
//
- (NSString*)selectedText
{
  return [self pageTextForSelection:YES inFormat:kPlainTextMIMEType];
}

//
// - pageTextForSelection: inFormat:
//
// Returns the text of the current selection (if selection is YES), or the
// whole page (if selection is NO). Choose "text/plain" as the format to get
// the text as it appears in the browser, without any formatting attributes, 
// or "text/html" to get the source code.
//
- (NSString*)pageTextForSelection:(BOOL)selection inFormat:(const char*)format
{
  nsCOMPtr<nsICommandManager> cmdManager = do_GetInterface(_webBrowser);
  if (!cmdManager) return NO;

  nsCOMPtr<nsICommandParams> params = do_CreateInstance(NS_COMMAND_PARAMS_CONTRACTID);
  if (!params) return NO;

  params->SetCStringValue("format", format);
  params->SetBooleanValue("selection_only", (selection ? PR_TRUE : PR_FALSE));

  nsresult rv = cmdManager->DoCommand("cmd_getContents", params, nsnull);
  if (NS_FAILED(rv))
    return NO;

  nsAutoString requestedText;
  params->GetStringValue("result", requestedText);

  return [NSString stringWith_nsAString:requestedText];
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types
{
  if ([types containsObject:NSStringPboardType] == NO)
    return NO;

  NSString* selectedText = [self selectedText];
  
  NSArray* typesDeclared = [NSArray arrayWithObject:NSStringPboardType];
  [pboard declareTypes:typesDeclared owner:nil];
    
  return [pboard setString:selectedText forType:NSStringPboardType];
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard
{
  NSArray* types = [pboard types];
  if (![types containsObject:NSStringPboardType])
    return NO;

  NSString* theText = [pboard stringForType:NSStringPboardType];
  nsAutoString textString;
  [theText assignTo_nsAString:textString];
  
  nsCOMPtr<nsICommandManager> cmdManager = do_GetInterface(_webBrowser);
  if (!cmdManager) return NO;

  nsCOMPtr<nsICommandParams> params = do_CreateInstance(NS_COMMAND_PARAMS_CONTRACTID);
  if (!params) return NO;
  
  params->SetStringValue("state_data", textString);
  nsresult rv = cmdManager->DoCommand("cmd_insertText", params, nsnull);
  
  return (BOOL)NS_SUCCEEDED(rv);
}

- (IBAction)reloadWithNewCharset:(NSString*)inCharset
{
  // set charset on document then reload the page (hopefully not hitting the network)
  nsCOMPtr<nsIDocCharset> charset ( do_QueryInterface([self docShell]) );
  if ( charset && inCharset ) {
    charset->SetCharset([inCharset UTF8String]);
    [self reload:nsIWebNavigation::LOAD_FLAGS_CHARSET_CHANGE];
  }
}

- (NSString*)currentCharset
{
#if 0
  nsCOMPtr<nsIWebBrowserFocus> wbf(do_QueryInterface(_webBrowser));
  if ( wbf ) {
    nsCOMPtr<nsIDOMWindow> focusedWindow;
    wbf->GetFocusedWindow(getter_AddRefs(focusedWindow));
    if ( focusedWindow ) {
      nsCOMPtr<nsIDOMDocument> domDoc;
      focusedWindow->GetDocument(getter_AddRefs(domDoc));
      nsCOMPtr<nsIDocument> doc ( do_QueryInterface(domDoc) );
      if ( doc ) {
        nsCAutoString charset;
        doc->GetDocumentCharacterSet(charset);
        return [NSString stringWithUTF8String:charset.get()];
      }
    }
  }
#endif

  nsCOMPtr<nsIDOMWindow> wind;
  _webBrowser->GetContentDOMWindow(getter_AddRefs(wind));
  if ( wind ) {
    nsCOMPtr<nsIDOMDocument> domDoc;
    wind->GetDocument(getter_AddRefs(domDoc));
    nsCOMPtr<nsIDocument> doc ( do_QueryInterface(domDoc) );
    if ( doc ) {
      const nsACString & charset = doc->GetDocumentCharacterSet();
      return [NSString stringWith_nsACString:charset];
    }
  }
  return nil;
}

#pragma mark -

- (BOOL)hasSSLStatus
{
  nsCOMPtr<nsISecureBrowserUI> secureUI([self secureBrowserUI]);
  nsCOMPtr<nsISSLStatusProvider> statusProvider = do_QueryInterface(secureUI);
  if (!statusProvider) return NO;

  nsCOMPtr<nsISupports> secStatus;
  statusProvider->GetSSLStatus(getter_AddRefs(secStatus));
  nsCOMPtr<nsISSLStatus> sslStatus = do_QueryInterface(secStatus);
  return (sslStatus.get() != NULL);
}

- (unsigned int)secretKeyLength
{
  nsCOMPtr<nsISecureBrowserUI> secureUI([self secureBrowserUI]);
  nsCOMPtr<nsISSLStatusProvider> statusProvider = do_QueryInterface(secureUI);
  if (!statusProvider) return 0;

  nsCOMPtr<nsISupports> secStatus;
  statusProvider->GetSSLStatus(getter_AddRefs(secStatus));
  nsCOMPtr<nsISSLStatus> sslStatus = do_QueryInterface(secStatus);

  PRUint32 sekritKeyLength = 0;
  if (sslStatus)
    sslStatus->GetSecretKeyLength(&sekritKeyLength);
  
  return sekritKeyLength;
}

- (NSString*)cipherName
{
  nsCOMPtr<nsISecureBrowserUI> secureUI([self secureBrowserUI]);
  nsCOMPtr<nsISSLStatusProvider> statusProvider = do_QueryInterface(secureUI);
  if (!statusProvider) return @"";

  nsCOMPtr<nsISupports> secStatus;
  statusProvider->GetSSLStatus(getter_AddRefs(secStatus));
  nsCOMPtr<nsISSLStatus> sslStatus = do_QueryInterface(secStatus);

  NSString* cipherNameString = @"";
  if (sslStatus)
  {
    nsCAutoString cipherName;
    sslStatus->GetCipherName(getter_Copies(cipherName));
    cipherNameString = [NSString stringWith_nsACString:cipherName];
  }
    
  return cipherNameString;
}

- (CHSecurityStatus)securityStatus
{
  nsCOMPtr<nsISecureBrowserUI> secureUI([self secureBrowserUI]);
  if (!secureUI) return CHSecurityInsecure;
  
  PRUint32 pageState;
  nsresult rv = secureUI->GetState(&pageState);
  if (NS_FAILED(rv))
    return CHSecurityBroken;

  if (pageState & nsIWebProgressListener::STATE_IS_BROKEN)
    return CHSecurityBroken;

  if (pageState & nsIWebProgressListener::STATE_IS_SECURE)
    return CHSecuritySecure;

  // return insecure by default
  // if (pageState & nsIWebProgressListener::STATE_IS_INSECURE)
  return CHSecurityInsecure;
}

- (CHSecurityStrength)securityStrength
{
  nsCOMPtr<nsISecureBrowserUI> secureUI([self secureBrowserUI]);
  if (!secureUI) return CHSecurityNone;
  
  PRUint32 pageState;
  nsresult rv = secureUI->GetState(&pageState);
  if (NS_FAILED(rv))
    return CHSecurityNone;

  if (!(pageState & nsIWebProgressListener::STATE_IS_SECURE))
    return CHSecurityNone;

  if (pageState & nsIWebProgressListener::STATE_SECURE_HIGH)
    return CHSecurityHigh;

  if (pageState & nsIWebProgressListener::STATE_SECURE_MED) // seems to be unused
    return CHSecurityMedium;

  if (pageState & nsIWebProgressListener::STATE_SECURE_LOW)
    return CHSecurityLow;

  return CHSecurityNone;
}

- (CertificateItem*)siteCertificate
{
  nsCOMPtr<nsISecureBrowserUI> secureUI([self secureBrowserUI]);
  nsCOMPtr<nsISSLStatusProvider> statusProvider = do_QueryInterface(secureUI);
  if (!statusProvider) return nil;

  nsCOMPtr<nsISupports> secStatus;
  statusProvider->GetSSLStatus(getter_AddRefs(secStatus));
  nsCOMPtr<nsISSLStatus> sslStatus = do_QueryInterface(secStatus);

  nsCOMPtr<nsIX509Cert> serverCert;
  if (sslStatus)
    sslStatus->GetServerCert(getter_AddRefs(serverCert));

  if (serverCert)
    return [CertificateItem certificateItemWithCert:serverCert];

  return nil;
}

#pragma mark -


- (already_AddRefed<nsISupports>)pageDescriptorByFocus:(BOOL)byFocus
{
  nsIDocShell* docShell;
  if (byFocus) {
    nsCOMPtr<nsIDOMWindow> focussedWindow = [self focussedDOMWindow];
    if (!focussedWindow)
      return NULL;
    nsCOMPtr<nsPIDOMWindow> privWin(do_QueryInterface(focussedWindow));
    if (!privWin)
      return NULL;
    docShell = privWin->GetDocShell(); // doesn't addref
  }
  else {
    docShell = [self docShell];     // doesn't addref
  }
  
  nsCOMPtr<nsIWebPageDescriptor> wpd = do_QueryInterface(docShell);
  if(!wpd)
    return NULL;

  nsISupports *desc = NULL;
  wpd->GetCurrentDescriptor(&desc);	// addrefs
  return desc;
}

- (void)setPageDescriptor:(nsISupports*)aDesc displayType:(PRUint32)aDisplayType
{
  nsCOMPtr<nsIWebPageDescriptor> wpd = do_QueryInterface([self docShell]);
  if(!wpd)
    return;

  wpd->LoadPage(aDesc, aDisplayType);
}

- (BOOL)canBecomeKeyView
{
  return YES;
}

- (BOOL)becomeFirstResponder
{
  if ([[self window] isKeyWindow])
    [self setActive:YES];
  return YES;
}

@end
