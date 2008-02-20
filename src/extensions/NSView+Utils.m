/* ***** BEGIN LICENSE BLOCK *****
 * Version: MPL 1.1/GPL 2.0/LGPL 2.1
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
 * for the specific language governing rights and limitations under the
 * License.
 *
 * The Original Code is Chimera code.
 *
 * The Initial Developer of the Original Code is
 * Netscape Communications Corporation.
 * Portions created by the Initial Developer are Copyright (C) 2002
 * the Initial Developer. All Rights Reserved.
 *
 * Contributor(s):
 *   Simon Fraser <sfraser@netscape.com>
 *
 * Alternatively, the contents of this file may be used under the terms of
 * either the GNU General Public License Version 2 or later (the "GPL"), or
 * the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
 * in which case the provisions of the GPL or the LGPL are applicable instead
 * of those above. If you wish to allow use of your version of this file only
 * under the terms of either the GPL or the LGPL, and not to allow others to
 * use your version of this file under the terms of the MPL, indicate your
 * decision by deleting the provisions above and replace them with the notice
 * and other provisions required by the GPL or the LGPL. If you do not delete
 * the provisions above, a recipient may use your version of this file under
 * the terms of any one of the MPL, the GPL or the LGPL.
 *
 * ***** END LICENSE BLOCK ***** */

#import "NSView+Utils.h"


@implementation NSView(CHViewUtils)

- (NSView*)swapFirstSubview:(NSView*)newSubview
{
  NSView* existingSubview = [self firstSubview];
  if (existingSubview == newSubview)
    return nil;

  [existingSubview retain];
  [existingSubview removeFromSuperview];
  [self addSubview:newSubview];
  [newSubview setFrame:[self bounds]];

  return [existingSubview autorelease];
}

- (NSView*)firstSubview
{
  NSArray* subviews = [self subviews];
  if ([subviews count] > 0)
    return [[self subviews] objectAtIndex:0];
  return 0;
}

- (NSView*)lastSubview
{
  NSArray* subviews = [self subviews];
  unsigned int numSubviews = [subviews count];
  if (numSubviews > 0)
    return [[self subviews] objectAtIndex:numSubviews - 1];
  return 0;
}

- (void)removeAllSubviews
{
  // clone the array to avoid issues with the array changing during the enumeration
  NSArray* subviewsArray = [[self subviews] copy];
  [subviewsArray makeObjectsPerformSelector:@selector(removeFromSuperview)];
  [subviewsArray release];
}

- (BOOL)hasSubview:(NSView*)inView
{
  return [[self subviews] containsObject:inView];
}

- (void)setFrameSizeMaintainingTopLeftOrigin:(NSSize)inNewSize
{
  if ([[self superview] isFlipped])
    [self setFrameSize:inNewSize];
  else
  {
    NSRect newFrame = [self frame];
    newFrame.origin.y -= (inNewSize.height - newFrame.size.height);
    newFrame.size = inNewSize;
    [self setFrame:newFrame];
  }
}

- (NSRect)subviewRectFromTopRelativeRect:(NSRect)inRect
{
  if ([self isFlipped])
    return inRect;

  NSRect theRect = inRect;
  theRect.origin.y = NSHeight([self bounds]) - NSMaxY(inRect);
  return theRect;
}


@end
