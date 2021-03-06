// =============================================================================
/*
    SubstrateMac

    Screensaver ported to Mac OS X by Warren Dodge of Hey Daddio!
    <http://www.heydaddio.com/>

    Original concept and code by
    Substrate Watercolor by J. Tarbell, June 2004, Albuquerque New Mexico
    Processing 0085 Beta syntax update, April 2005
    <http://complexification.net/>

    Curved crack drawing adapted from xscreensaver version by David Agraz Jan 2005
    The following license applies to the curved crack drawing code:
    xscreensaver, Copyright (c) 1997, 1998, 2002 Jamie Zawinski <jwz@jwz.org>
    Permission to use, copy, modify, distribute, and sell this software 
    and its documentation for any purpose is hereby granted without fee, 
    provided that the above copyright notice appear in all copies and 
    that both that copyright notice and this permission notice appear 
    in supporting documentation. No representations are made about the 
    suitability of this software for any purpose.  It is provided "as is" 
    without express or implied warranty.


    HeySubstrateView.m
    SubstrateMac/SubstrateiPhone Projects

    View for fancy drawing.
*/
// -----------------------------------------------------------------------------

#import "HeySubstrateView.h"
#import "HeySubstrateCrack.h"
#import "HeySubstrateColorPalette.h"


// -----------------------------------------------------------------------------
// MARK: Constants

// Key strings for defaults.
static NSString * const defaultsKeyNumberOfCracks = @"NumberOfCracks";
static NSString * const defaultsKeySpeedOfCracking = @"SpeedOfCracking";
static NSString * const defaultsKeyAmountOfSand = @"AmountOfSand";
static NSString * const defaultsKeyDensityOfDrawing = @"DensityOfDrawing";
static NSString * const defaultsKeyPauseBetweenDrawings = @"PauseBetweenDrawings";
static NSString * const defaultsKeyDrawCracksOnly = @"DrawCracksOnly";
static NSString * const defaultsKeyPercentageOfCurvedCracks = @"PercentageOfCurvedCracks";
static NSString * const defaultsKeySandColors = @"SandColors";
static NSString * const optionSheetNibName = @"SubstrateMacOptions";

#if TARGET_OS_IPHONE
static const CGSize infoSize = {32.0f, 32.0f};      // Size of info icon/button.
static const NSInteger infoFadeFrames = 30 * 2;     // Fade time of info button.
#endif


// -----------------------------------------------------------------------------
// MARK: Private Category Interface

@interface HeySubstrateView (Private)

- (BOOL)internalInitializer;
#if TARGET_OS_IPHONE
- (CGFloat)alphaForInfo;
- (void)showInfo:(BOOL)immediate;
#endif

@end


// -----------------------------------------------------------------------------
// MARK: Private Category Implementation

@implementation HeySubstrateView (Private)

// Initializer called from all inits.
- (BOOL)internalInitializer
{
    BOOL success = YES;
    
    // Register/load defaults.
    CGFloat start;
    CGFloat density;
#if TARGET_OS_IPHONE
    NSUserDefaults *defaults;
    defaults = [NSUserDefaults standardUserDefaults];
    start = 3.0f;
    density = 50000.0f;
    touchedCrackOrigins = [[NSMutableArray array] retain];
#else
    ScreenSaverDefaults *defaults;
    defaults = [ScreenSaverDefaults defaultsForModuleWithName:HeySubstrateMacModuleName];
    start = 11.0f;
    density = 100000.0f;
#endif
    palette = [[HeySubstrateColorPalette alloc] init];
    NSMutableArray *colorStrings = [[NSMutableArray alloc] initWithCapacity:[[palette heyColors] count]];
    for (HEYCOLOR *c in [palette heyColors])
    {
        [colorStrings addObject:[c stringFromHeyColor]];
    }
    [defaults registerDefaults:
        [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithFloat:(float)start],    defaultsKeyNumberOfCracks,
            [NSNumber numberWithFloat:1.0f],            defaultsKeySpeedOfCracking,
            [NSNumber numberWithFloat:-0.046f],         defaultsKeyAmountOfSand,
            [NSNumber numberWithFloat:(float)density],  defaultsKeyDensityOfDrawing,
            [NSNumber numberWithFloat:10.0f],           defaultsKeyPauseBetweenDrawings,
            @"NO",                                      defaultsKeyDrawCracksOnly,
            [NSNumber numberWithFloat:15.0f],       defaultsKeyPercentageOfCurvedCracks,
            colorStrings,                               defaultsKeySandColors,
            nil]
     ];
    [colorStrings release];
    opts.numberOfCracks        = [defaults floatForKey:defaultsKeyNumberOfCracks];
    opts.speedOfCracking       = [defaults floatForKey:defaultsKeySpeedOfCracking];
    opts.amountOfSand          = [defaults floatForKey:defaultsKeyAmountOfSand];
    opts.densityOfDrawing      = [defaults floatForKey:defaultsKeyDensityOfDrawing];
    opts.pauseBetweenDrawings  = [defaults floatForKey:defaultsKeyPauseBetweenDrawings];
    opts.drawCracksOnly        = [defaults boolForKey: defaultsKeyDrawCracksOnly];
    opts.percentCurves         = [defaults floatForKey:defaultsKeyPercentageOfCurvedCracks];
    //opts.colors                = [[defaults arrayForKey:defaultsKeySandColors] retain];
    NSArray *defColorStrings = [defaults arrayForKey:defaultsKeySandColors];
    NSMutableArray *colors = [[NSMutableArray alloc] initWithCapacity:[defColorStrings count]];
    for (NSString *cs in defColorStrings)
    {
        HEYCOLOR *c = [HEYCOLOR HeyColorWithString:cs];
        if (c)
        {
            [colors addObject:c];
        }
    }
    opts.colors = colors;
    [palette setHeyColors:opts.colors];
    
    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
    {
        viewWidth = (float)[self frame].size.width * [[UIScreen mainScreen] scale];
        viewHeight = (float)[self frame].size.height * [[UIScreen mainScreen] scale];
    }
    else
    {
        viewWidth = (float)[self frame].size.width;
        viewHeight = (float)[self frame].size.height;
    }

    maxNumCracks = 100;
    iterationsDone = 0;
    drawingPaused = NO;
    framesPaused = 0;
    
    // crackAngleGrid contains the (single, latest) angle of travel of any 
    //  cracks that pass through the corresponding pixel.
    crackAngleGrid = (int*)malloc(sizeof(int) * viewWidth * viewHeight);
    if (!crackAngleGrid)
    {
        success = NO;
    }
    // Array of crack objects.
    crackArray = [NSMutableArray arrayWithCapacity:maxNumCracks];
    [crackArray retain];
    if (!crackArray)
    {
        success = NO;
    }
    // Color of cracks.
    if (!HeySubstrateCrackColor)
    {
        //crackColor = [NSColor colorWithDeviceRed:0.0f green:0.0f blue:0.0f alpha:0.5f];
        HeySubstrateCrackColor = [HEYCOLOR HeyColorWithRed:0.0f green:0.0f blue:0.0f alpha:0.5f];
        if (!HeySubstrateCrackColor)
            success = NO;
    }
    [HeySubstrateCrackColor retain];

#if TARGET_OS_IPHONE    
    // Load the info icon.
    infoIcon = [[UIImage imageNamed:@"infoicon.png"] retain];
    if (!infoIcon)
        success = NO;
    infoRect = CGRectMake(self.bounds.size.width - infoSize.width, 
                          self.bounds.size.height - infoSize.height, 
                          infoSize.width, infoSize.height);
    infoFadeState = kHeySubstrateFadeOff;
#endif    
    // Bail out if errors.
    if (success == NO)
    {
        [HeySubstrateCrackColor release], HeySubstrateCrackColor = nil;
        [crackArray release], crackArray = nil;
        free(crackAngleGrid), crackAngleGrid = NULL;
        //[self release];
    }
    return success;
}


#if TARGET_OS_IPHONE
// Return the correct alpha value for the Info icon/button.
- (CGFloat)alphaForInfo
{
    // Maximum alpha for the info icon for esthetics.
    static const CGFloat maxInfoAlpha = 0.75f;    
    
    CGFloat infoAlpha;
    switch (infoFadeState) 
    {
      case kHeySubstrateFadeOff:
          infoAlpha = 0.0f;
          break;
      case kHeySubstrateFadeIn:
          infoAlpha = maxInfoAlpha - (maxInfoAlpha * (CGFloat)infoFadeCountdown / (CGFloat)infoFadeFrames);
          break;
      case kHeySubstrateFadeOn:
          infoAlpha = maxInfoAlpha;
          break;
      case kHeySubstrateFadeOut:
          infoAlpha = (maxInfoAlpha * (CGFloat)infoFadeCountdown / (CGFloat)infoFadeFrames);
          break;
      default:
          infoAlpha = 0.0f;
          break;
    }
    return infoAlpha;
}


// Handle showing the Info icon/button with fade in and out.
- (void)showInfo:(BOOL)immediate
{
    switch (infoFadeState) 
    {
      case kHeySubstrateFadeOff:
          if (immediate)
              infoFadeState = kHeySubstrateFadeOn;
          else
              infoFadeState = kHeySubstrateFadeIn;
          infoFadeCountdown = infoFadeFrames;
          break;
      case kHeySubstrateFadeIn:
          if (immediate)
          {
              infoFadeState = kHeySubstrateFadeOn;
              infoFadeCountdown = infoFadeFrames;
          }
          break;
      case kHeySubstrateFadeOn:
          infoFadeCountdown = infoFadeFrames;
          break;
      case kHeySubstrateFadeOut:
          if (immediate)
          {
              infoFadeState = kHeySubstrateFadeOn;
              infoFadeCountdown = infoFadeFrames;
          }
          else
          {
              infoFadeState = kHeySubstrateFadeIn;
              infoFadeCountdown = infoFadeFrames - infoFadeCountdown;
          }
          break;
      default:
          break;
    }
}
#endif

@end


// =============================================================================


// -----------------------------------------------------------------------------
// MARK: HeySubstrateMacView

@implementation HeySubstrateView


// -----------------------------------------------------------------------------
// MARK: Init and dealloc

// Designated initializer.
#if TARGET_OS_IPHONE
- (id)initWithFrame:(CGRect)frame
{
    BOOL success = NO;
    if ((self = [super initWithFrame:frame]))
    {
        success = [self internalInitializer];
    }
    if (!success)
    {
        [self release];
        return nil;
    }
    return self;
}
#else
- (id)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    BOOL success = NO;
    if ((self = [super initWithFrame:frame isPreview:isPreview]))
        success = [self internalInitializer];
    if (!success)
    {
        [self release];
        return nil;
    }
    return self;
}
#endif


// NSCoding initializer
- (id)initWithCoder:(NSCoder *)coder
{
    BOOL success = NO;
    if ((self = [super initWithCoder:coder]))
        success = [self internalInitializer];
    if (!success)
    {
        [self release];
        return nil;
    }
    return self;
}


// Destroy the view.
- (void) dealloc 
{
#if TARGET_OS_IPHONE
    if (qLayer)
    {
        CGLayerRelease(qLayer);
        qLayer = NULL;
    }
    [palette release], palette = nil;
    [infoIcon release], infoIcon = nil;
    [touchedCrackOrigins release], touchedCrackOrigins = nil;
#endif
    [opts.colors release];
    [numberOfCracksSlider release], numberOfCracksSlider = nil;
    [speedOfCrackingSlider release], speedOfCrackingSlider = nil;
    [amountOfSandSlider release], amountOfSandSlider = nil;
    [densityOfDrawingSlider release], densityOfDrawingSlider = nil;
    [pauseBetweenDrawingsSlider release], pauseBetweenDrawingsSlider = nil;
    [drawCracksOnlyOption release], drawCracksOnlyOption = nil;
    [percentCurvedSlider release], percentCurvedSlider = nil;
    [optionSheet release], optionSheet = nil;
    
    // This view should be the last thing to be deallocated, so should probably
    //  take the singleton HeySubstrateCrackColor with it.
    [HeySubstrateCrackColor release], HeySubstrateCrackColor = nil;   
    [crackArray release], crackArray = nil;
    free(crackAngleGrid), crackAngleGrid = NULL;

    [super dealloc];
}


// -----------------------------------------------------------------------------
// MARK: Accessors

// Return CGPointZero if no points.
- (CGPoint)nextCrackOrigin
{
    CGPoint nextP = CGPointZero;
    if ([touchedCrackOrigins count] > 0)
    {
        nextP = [(NSValue *)[touchedCrackOrigins objectAtIndex:0] CGPointValue];
        [touchedCrackOrigins removeObjectAtIndex:0];
    }
    return nextP;
}


- (HeySubstrateColorPalette *)palette
{
    return palette;
}

- (void)setPalette:(HeySubstrateColorPalette *)aPalette
{
    (void)aPalette;
    NSLog(@"CONSIDER IMPLEMENTING %@:%@", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
}


- (NSString *)message
{
    return [[displayMessage copy] autorelease];
}

- (void)setMessage:(NSString *)newMessage
{
    if (![displayMessage isEqualToString:newMessage])
    {
        [displayMessage release];
        displayMessage = [newMessage copy];
    }
    [self setNeedsDisplay];
}

- (void)clearMessage
{
    [self setMessage:nil];
}


// -----------------------------------------------------------------------------
// MARK: Drawing and animation methods

// Make a new crack if not at maximum number already.
- (void)makeACrack 
{
    if (currNumCracks < opts.numberOfCracks ) 
    {
        HeySubstrateCrack *newCrack;
        newCrack = [[HeySubstrateCrack alloc] initWithSSView:self];
        [crackArray insertObject:newCrack atIndex:currNumCracks++];
        [newCrack release];
    }
}


- (void)startAnimation 
{
    [self setupAnimation];
#if TARGET_OS_IPHONE
#else
    [super startAnimation];
#endif
}


- (void)stopAnimation 
{
#if TARGET_OS_IPHONE
#else
    [super stopAnimation];
#endif
}


- (void)restartAnimation 
{
    [crackArray removeAllObjects];
    bgCleared = NO;
    drawingPaused = NO;
    framesPaused = 0;
    iterationsDone = 0;
    [self setupAnimation];
}


- (void)setupAnimation 
{
    // Erase crackAngleGrid
    int x, y;
    for (y = 0; y < viewHeight; y++) 
    {
        for (x = 0; x < viewWidth; x++) 
        {
            crackAngleGrid[y * viewWidth + x] = cagEmptyFlag;     
        }
    }
    
    // Make random crack seeds
    int i, k;
    for (k = 0; k < 16; k++) 
    {
        i = (int)(arc4random() % (viewWidth * viewHeight));
        crackAngleGrid[i] = (int)(arc4random() % 360);
    }
    
    // Make just three cracks to start with
    int c;
    currNumCracks = 0;
    for (c = 0; c < 3; c++) 
    {
        [self makeACrack];
    }
    return;
}


//- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx
//{
//}


//- (void)displayLayer:(CALayer *)layer
//{
//    [layer setContents:(id)offscreenBitmapImage];    
//}


- (void)drawRect:(HEYRECT)rect 
{
#if TARGET_OS_IPHONE
    (void)rect;
    if (qLayer == nil)
    {
        CGFloat scaleFactor = 1.0f;
        if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
        {
            scaleFactor = [[UIScreen mainScreen] scale];
        }
        CGSize sz = CGSizeMake([self bounds].size.width * scaleFactor, [self bounds].size.height * scaleFactor);
        qLayer = CGLayerCreateWithContext(UIGraphicsGetCurrentContext(), sz, NULL);
    }
    
    [self animateOneFrame];
    
    if (saveNextFrameToPhotoLibrary)
    {
        saveNextFrameToPhotoLibrary = NO;
        CGSize sz = CGLayerGetSize(qLayer);
        size_t w = sz.width;
        size_t h = sz.height;
        int bitsPerPixel = 8;
        int bytesPerRow = w * 4;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        void * bmpData = malloc(bytesPerRow * h);
        CGContextRef bmp = CGBitmapContextCreate(bmpData, w, h, bitsPerPixel, bytesPerRow, space, (kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst));
        CGColorSpaceRelease(space);
        CGContextDrawLayerInRect(bmp, CGRectMake(0.0f, 0.0f, sz.width, sz.height), qLayer);
        CGImageRef cgImg = CGBitmapContextCreateImage(bmp);
        UIImage *img = [UIImage imageWithCGImage:cgImg];
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
        CGImageRelease(cgImg);
        CGContextRelease(bmp);
        free(bmpData);
    }

    CGContextDrawLayerInRect(UIGraphicsGetCurrentContext(), [self bounds], qLayer);
    if (infoFadeState != kHeySubstrateFadeOff)
    {
        [infoIcon drawInRect:infoRect blendMode:kCGBlendModeNormal alpha:[self alphaForInfo]];
    }
    if (displayMessage)
    {
        //CGRect msgRect = CGRectMake(0.0f, 456.0f, 320.0f, 24.0f);
        CGRect viewBounds = [self bounds];
        CGFloat msgHeight = 24.0f;
        CGRect msgRect = CGRectMake(viewBounds.origin.x, 
                                    viewBounds.size.height - msgHeight, 
                                    viewBounds.size.width, 
                                    msgHeight);
        [displayMessage drawInRect:msgRect withFont:[UIFont boldSystemFontOfSize:18.0f] lineBreakMode:UILineBreakModeClip alignment:UITextAlignmentCenter];
    }
#else
    [super drawRect:rect];
#endif
}


- (void)animateOneFrame 
{
    CGContextRef ctx = nil;
    // Clear background
    // Warm up the canvas a bit: RGB:255/251/239
#if TARGET_OS_IPHONE
    ctx = CGLayerGetContext(qLayer);
    if (bgCleared == NO) 
    {
        CGContextSetFillColorWithColor(ctx, [[HEYCOLOR HeyColorWithRed:1.0f green:0.9843f blue:0.9373f alpha:1.0f] CGColor]);
        CGFloat scaleFactor = 1.0f;
        if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
        {
            scaleFactor = [[UIScreen mainScreen] scale];
        }
        CGRect b = [self bounds];
        CGContextFillRect(ctx, CGRectMake(b.origin.x * scaleFactor, b.origin.y * scaleFactor, b.size.width * scaleFactor, b.size.height * scaleFactor));
        bgCleared = YES;
    }
#else
    if (bgCleared == NO) 
    {
        [[HEYCOLOR HeyColorWithRed:1.0f green:0.9843f blue:0.9373f alpha:1.0f] set];
        [NSBezierPath fillRect:[self frame]];
        bgCleared = YES;
    }
#endif
    
    int i;
    int spdLoops;
    
    if (drawingPaused) 
    {
        if (framesPaused++ >= framesToPause) 
        {
            drawingPaused = NO;
            framesPaused = 0;
            iterationsDone = 0;
            [self restartAnimation];
        }
    } 
    else 
    {
        // crack all cracks
        for (spdLoops = (int)opts.speedOfCracking; spdLoops > 0; spdLoops--) 
        {
            for (i = 0; i < currNumCracks; i++) 
            {
                iterationsDone++;
                [[crackArray objectAtIndex:i] setQLayerContext:ctx];
                [[crackArray objectAtIndex:i] move];
            }
            if (iterationsDone >= opts.densityOfDrawing) 
            {
                drawingPaused = YES;
                framesPaused = 0;
                iterationsDone = 0;
                framesToPause = (int)opts.pauseBetweenDrawings * HeySubstrateAnimationFPS;
            }
        }
    }
#if TARGET_OS_IPHONE
    // Update alpha fading for info icon.
    infoFadeCountdown--;
    switch (infoFadeState) 
    {
      case kHeySubstrateFadeOff:
          infoFadeCountdown = infoFadeFrames;
          break;
      case kHeySubstrateFadeIn:
          if (infoFadeCountdown <= 0)
          {
              infoFadeState = kHeySubstrateFadeOn;
              infoFadeCountdown = infoFadeFrames;
          }
          break;
      case kHeySubstrateFadeOn:
          if (infoFadeCountdown <= 0)
          {
              infoFadeState = kHeySubstrateFadeOut;
              infoFadeCountdown = infoFadeFrames;
          }
          break;
      case kHeySubstrateFadeOut:
          if (infoFadeCountdown <= 0)
          {
              infoFadeState = kHeySubstrateFadeOff;
              infoFadeCountdown = infoFadeFrames;
          }
          break;
      default:
          break;
    }
#endif
}


- (BOOL)isOpaque 
{
    return YES;
}


#if TARGET_OS_IPHONE
#else

- (BOOL)hasConfigureSheet 
{
    return YES;
}


// Set up the option sheet.
- (NSWindow*)configureSheet 
{
    ScreenSaverDefaults *defaults;
    defaults = [ScreenSaverDefaults defaultsForModuleWithName:HeySubstrateMacModuleName];
    
    if (!optionSheet) 
    {
        if (![NSBundle loadNibNamed:optionSheetNibName owner:self]) 
        {
            NSLog(@"Unable to load options configuration sheet.");
        }
    }
    [numberOfCracksSlider       setFloatValue:[defaults floatForKey:defaultsKeyNumberOfCracks]];
    [speedOfCrackingSlider      setFloatValue:[defaults floatForKey:defaultsKeySpeedOfCracking]];
    [amountOfSandSlider         setFloatValue:[defaults floatForKey:defaultsKeyAmountOfSand]];
    [densityOfDrawingSlider     setFloatValue:[defaults floatForKey:defaultsKeyDensityOfDrawing]];
    [pauseBetweenDrawingsSlider setFloatValue:[defaults floatForKey:defaultsKeyPauseBetweenDrawings]];
    [drawCracksOnlyOption       setState:     [defaults boolForKey: defaultsKeyDrawCracksOnly]];
    [percentCurvedSlider        setFloatValue:[defaults floatForKey:defaultsKeyPercentageOfCurvedCracks]];
    return optionSheet;
}


// Save the options.
- (IBAction)okClick:(id)sender 
{
    (void)sender;
    ScreenSaverDefaults *defaults;
    defaults = [ScreenSaverDefaults defaultsForModuleWithName:HeySubstrateMacModuleName];
    [defaults setFloat:[numberOfCracksSlider        floatValue] forKey:defaultsKeyNumberOfCracks];
    [defaults setFloat:[speedOfCrackingSlider       floatValue] forKey:defaultsKeySpeedOfCracking];
    [defaults setFloat:[amountOfSandSlider          floatValue] forKey:defaultsKeyAmountOfSand];
    [defaults setFloat:[densityOfDrawingSlider      floatValue] forKey:defaultsKeyDensityOfDrawing];
    [defaults setFloat:[pauseBetweenDrawingsSlider  floatValue] forKey:defaultsKeyPauseBetweenDrawings];
    [defaults setBool: [drawCracksOnlyOption        state]      forKey:defaultsKeyDrawCracksOnly];
    [defaults setFloat:[percentCurvedSlider         floatValue] forKey:defaultsKeyPercentageOfCurvedCracks];

// !!!: needs to be updated for sand colors
    
    [defaults synchronize];

    [[NSApplication sharedApplication] endSheet:optionSheet];
    
    opts.numberOfCracks        = [defaults floatForKey:defaultsKeyNumberOfCracks];
    opts.speedOfCracking       = [defaults floatForKey:defaultsKeySpeedOfCracking];
    opts.amountOfSand          = [defaults floatForKey:defaultsKeyAmountOfSand];
    opts.densityOfDrawing      = [defaults floatForKey:defaultsKeyDensityOfDrawing];
    opts.pauseBetweenDrawings  = [defaults floatForKey:defaultsKeyPauseBetweenDrawings];
    opts.drawCracksOnly        = [defaults boolForKey: defaultsKeyDrawCracksOnly];
    opts.percentCurves         = [defaults floatForKey:defaultsKeyPercentageOfCurvedCracks];
    
    [self restartAnimation];
    return;
}


- (IBAction)cancelClick:(id)sender 
{
    (void)sender;
    [[NSApplication sharedApplication] endSheet:optionSheet];
}
#endif


- (int)optionPercentCurves 
{
    return opts.percentCurves;
}


- (float)optionAmountOfSand 
{
    return opts.amountOfSand;
}


- (BOOL)optionDrawCracksOnly 
{
    return opts.drawCracksOnly;
}


- (int)viewWidth 
{
    return viewWidth;
}


- (int)viewHeight 
{
    return viewHeight;
}


- (int *)crackAngleGrid 
{
    return crackAngleGrid;
}


- (void)getOptions:(HeySubstrateOptions *)options
{
    options->numberOfCracks       = opts.numberOfCracks;
    options->speedOfCracking      = opts.speedOfCracking;
    options->amountOfSand         = opts.amountOfSand;
    options->densityOfDrawing     = opts.densityOfDrawing; 
    options->pauseBetweenDrawings = opts.pauseBetweenDrawings;
    options->percentCurves        = opts.percentCurves;
    options->drawCracksOnly       = opts.drawCracksOnly;
    options->colors               = [[opts.colors retain] autorelease];
}


- (void)setOptions:(HeySubstrateOptions *)options
{
    opts.numberOfCracks       = options->numberOfCracks;
    opts.speedOfCracking      = options->speedOfCracking;
    opts.amountOfSand         = options->amountOfSand;
    opts.densityOfDrawing     = options->densityOfDrawing; 
    opts.pauseBetweenDrawings = options->pauseBetweenDrawings;
    opts.percentCurves        = options->percentCurves;
    opts.drawCracksOnly       = options->drawCracksOnly;
    if (opts.colors != options->colors)
    {
        [opts.colors release];
        opts.colors = [options->colors retain];
    }
    [self writeOptions];
}


-(void)writeOptions
{
    NSUserDefaults *defaults;
    defaults = [NSUserDefaults standardUserDefaults];
    [defaults setFloat:opts.numberOfCracks forKey:defaultsKeyNumberOfCracks];
    [defaults setFloat:opts.speedOfCracking forKey:defaultsKeySpeedOfCracking];
    [defaults setFloat:opts.amountOfSand forKey:defaultsKeyAmountOfSand];
    [defaults setFloat:opts.densityOfDrawing forKey:defaultsKeyDensityOfDrawing];
    [defaults setFloat:opts.pauseBetweenDrawings forKey:defaultsKeyPauseBetweenDrawings];
    [defaults setBool:opts.drawCracksOnly forKey:defaultsKeyDrawCracksOnly];
    [defaults setFloat:opts.percentCurves forKey:defaultsKeyPercentageOfCurvedCracks];
    
    NSMutableArray *colorStrings = [NSMutableArray arrayWithCapacity:[opts.colors count]];
    for (HEYCOLOR *c in opts.colors)
    {
        [colorStrings addObject:[c stringFromHeyColor]];
    }
    [defaults setObject:colorStrings forKey:defaultsKeySandColors];

    [defaults synchronize];
}


- (void)saveFrameToLibrary
{
    saveNextFrameToPhotoLibrary = YES;
}


// -----------------------------------------------------------------------------
// MARK: Touches and hit testing
#if TARGET_OS_IPHONE
// Hit test the touches
- (BOOL)hitTestTouches:(NSSet *)touches withEvent:(UIEvent *)event
{
    (void)event;
    UITouch *touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView:self];
    if (CGRectContainsPoint(infoRect, touchPoint))
    {
        [self showInfo:YES];
        [(HeySubstrateAppDelegate *)[[UIApplication sharedApplication] delegate] showSettings];
        return YES;
    }
    else
    {
        [self showInfo:NO];
        [touchedCrackOrigins addObject:[NSValue valueWithCGPoint:touchPoint]];
        return NO;
    }
}


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self hitTestTouches:touches withEvent:event];
}


- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self hitTestTouches:touches withEvent:event];
}


- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self hitTestTouches:touches withEvent:event];
}


- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    (void)touches;
    (void)event;
    // Do nothing.
}
#endif


@end


// End of HeySubstrateView.m
// =============================================================================
