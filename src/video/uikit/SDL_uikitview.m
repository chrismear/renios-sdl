 /*
  Simple DirectMedia Layer
  Copyright (C) 1997-2012 Sam Lantinga <slouken@libsdl.org>

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/
#include "SDL_config.h"

#if SDL_VIDEO_DRIVER_UIKIT

#include "SDL_uikitview.h"

#include "../../events/SDL_keyboard_c.h"
#include "../../events/SDL_mouse_c.h"
#include "../../events/SDL_touch_c.h"

#if SDL_IPHONE_KEYBOARD
#include "keyinfotable.h"
#include "SDL_uikitappdelegate.h"
#include "SDL_uikitmodes.h"
#include "SDL_uikitwindow.h"
#endif

@implementation SDL_uikitview

- (void)dealloc
{
    [super dealloc];
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame: frame];

#if SDL_IPHONE_KEYBOARD
    [self initializeKeyboard];
#endif

    self.multipleTouchEnabled = YES;

    SDL_Touch touch;
    touch.id = 0; //TODO: Should be -1?

    //touch.driverdata = SDL_malloc(sizeof(EventTouchData));
    //EventTouchData* data = (EventTouchData*)(touch.driverdata);

    touch.x_min = 0;
    touch.x_max = 1;
    touch.native_xres = touch.x_max - touch.x_min;
    touch.y_min = 0;
    touch.y_max = 1;
    touch.native_yres = touch.y_max - touch.y_min;
    touch.pressure_min = 0;
    touch.pressure_max = 1;
    touch.native_pressureres = touch.pressure_max - touch.pressure_min;

    touchId = SDL_AddTouch(&touch, "IPHONE SCREEN");

    return self;

}

- (CGPoint)touchLocation:(UITouch *)touch shouldNormalize:(BOOL)normalize
{
    CGPoint point = [touch locationInView: self];

    // Get the display scale and apply that to the input coordinates
    SDL_Window *window = self->viewcontroller.window;
    SDL_VideoDisplay *display = SDL_GetDisplayForWindow(window);
    SDL_DisplayModeData *displaymodedata = (SDL_DisplayModeData *) display->current_mode.driverdata;

    if (normalize) {
        CGRect bounds = [self bounds];
        point.x /= bounds.size.width;
        point.y /= bounds.size.height;
    } else {
        point.x *= displaymodedata->scale;
        point.y *= displaymodedata->scale;
    }
    return point;
}

- (void)sendLeftMouseDown
{
    SDL_SendMouseButton(NULL, SDL_PRESSED, SDL_BUTTON_LEFT);
    leftMouseDownSent = SDL_TRUE;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    NSEnumerator *enumerator = [touches objectEnumerator];
    UITouch *touch = (UITouch*)[enumerator nextObject];

    while (touch) {
        if (!leftFingerDown && !rightFingerDown) {
            CGPoint locationInView = [self touchLocation:touch shouldNormalize:NO];

            twoFingerTouch = SDL_FALSE;

            /* Queue mouse-down event to trigger after a short delay,
             * so we can cancel it should a second finger touch the 
             * surface
             */
             leftMouseDownSent = SDL_FALSE;
             [self performSelector:@selector(sendLeftMouseDown) withObject:nil afterDelay:0.1];

            /* send moved event */
            SDL_SendMouseMotion(NULL, 0, locationInView.x, locationInView.y);

            leftFingerDown = (SDL_FingerID)touch;
        } else if (!rightFingerDown) {
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendLeftMouseDown) object:nil];
            rightFingerDown = (SDL_FingerID)touch;
            twoFingerTouch = SDL_TRUE;
        }

        CGPoint locationInView = [self touchLocation:touch shouldNormalize:YES];
#ifdef IPHONE_TOUCH_EFFICIENT_DANGEROUS
        // FIXME: TODO: Using touch as the fingerId is potentially dangerous
        // It is also much more efficient than storing the UITouch pointer
        // and comparing it to the incoming event.
        SDL_SendFingerDown(touchId, (SDL_FingerID)touch,
                           SDL_TRUE, locationInView.x, locationInView.y,
                           1);
#else
        int i;
        for(i = 0; i < MAX_SIMULTANEOUS_TOUCHES; i++) {
            if (finger[i] == NULL) {
                finger[i] = touch;
                SDL_SendFingerDown(touchId, i,
                                   SDL_TRUE, locationInView.x, locationInView.y,
                                   1);
                break;
            }
        }
#endif
        touch = (UITouch*)[enumerator nextObject];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    NSEnumerator *enumerator = [touches objectEnumerator];
    UITouch *touch = (UITouch*)[enumerator nextObject];

    while(touch) {

        if ((SDL_FingerID)touch == leftFingerDown) {
            if (twoFingerTouch == SDL_TRUE) {
                if (rightFingerDown) {
                    // Right finger is still being held down
                    if (leftMouseDownSent == SDL_TRUE) {
                        /* 
                         * This was a touch sequence where a second finger touched the screen,
                         * but did so more than 0.1s after the first finger touched the screen.
                         * This means we effectively ignore the second finger, and treat the
                         * whole touch sequence as if it were a just a single-finger touch.
                         */
                        SDL_SendMouseButton(NULL, SDL_RELEASED, SDL_BUTTON_LEFT);

                        // End of mouse motion; reset pointer to 0,0
                        SDL_SendMouseMotion(NULL, 0, 0, 0);
                    } else {
                        /*
                         * This touch sequence involved two fingers being placed down within
                         * 0.1s of each other, so we treat it as a two-finger touch.
                         * Although the first finger has been lifted here, the second
                         * finger is still touching the screen, so we will do nothing until
                         * the second finger finishes its touch.
                         */
                    }
                } else {
                    /*
                     * This was a two-finger touch sequence, but the second (right) finger
                     * has already been lifted.
                     */
                    if (leftMouseDownSent == SDL_TRUE) {
                        /*
                         * Two fingers were involved, but the second finger touched the screen
                         * more than 0.1s after the first finger, so we effectively ignore
                         * the presence of the second finger. Hence we treat this as a single-
                         * finger touch.
                         */
                        SDL_SendMouseButton(NULL, SDL_RELEASED, SDL_BUTTON_LEFT);

                        // End of mouse motion; reset pointer to 0,0
                        SDL_SendMouseMotion(NULL, 0, 0, 0);
                    } else {
                        /*
                         * The two fingers touched the screen within 0.1s of each other,
                         * and we are now seeing the last finger being removed from the
                         * screen. We treat this as a two-finger tap == right-click.
                         */
                        SDL_SendMouseButton(NULL, SDL_PRESSED, SDL_BUTTON_RIGHT);
                        SDL_SendMouseButton(NULL, SDL_RELEASED, SDL_BUTTON_RIGHT);

                        // End of mouse motion; reset pointer to 0,0
                        SDL_SendMouseMotion(NULL, 0, 0, 0);                    }
                    /*
                     * As this is the end of the touch sequence, we can reset our state
                     * variables.
                     */
                    twoFingerTouch = SDL_FALSE;
                    leftMouseDownSent = SDL_FALSE;
                }
            } else {
                // No second finger was involved in ths touch sequence.
                if (leftMouseDownSent == SDL_TRUE) {
                    SDL_SendMouseButton(NULL, SDL_RELEASED, SDL_BUTTON_LEFT);


                    // End of mouse motion; reset pointer to 0,0
                    SDL_SendMouseMotion(NULL, 0, 0, 0);
                } else {
                    // The touch start and touch end occurred before the delayed
                    // mouse-down had a chance to fire. Cancel it, and do
                    // the mouse down and mouse up together here.
                    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendLeftMouseDown) object:nil];
                    SDL_SendMouseButton(NULL, SDL_PRESSED, SDL_BUTTON_LEFT);
                    SDL_SendMouseButton(NULL, SDL_RELEASED, SDL_BUTTON_LEFT);

                    // End of mouse motion; reset pointer to 0,0
                    SDL_SendMouseMotion(NULL, 0, 0, 0);
                }
                leftMouseDownSent = SDL_FALSE;
            }
            leftFingerDown = 0;
        } else if ((SDL_FingerID)touch == rightFingerDown) {
            if (leftFingerDown) {
                /*
                 * This was a two-finger touch sequence, but the first (left) finger
                 * is still being held down. So do nothing here.
                 */
            } else {
                /*
                 * This was a two-finger touch sequence, and we are the last finger to be lifted.
                 */
                if (leftMouseDownSent == SDL_TRUE) {
                    // Do nothing. Second finger started touching too late, so we treat
                    // the whole touch sequence as a one-finger touch.
                } else {
                    /*
                     * A two-finger touch that started with both fingers within
                     * 0.1s of each other (leftMouseDown was cancelled), and 
                     * we are the last finger to be lifted. So, trigger our
                     * two-finger tap event, which is equivalent to a right-click.
                     */
                    SDL_SendMouseButton(NULL, SDL_PRESSED, SDL_BUTTON_RIGHT);
                    SDL_SendMouseButton(NULL, SDL_RELEASED, SDL_BUTTON_RIGHT);

                    // End of mouse motion; reset pointer to 0,0
                    SDL_SendMouseMotion(NULL, 0, 0, 0);
                }
                // End of touch sequence, so reset variables.
                leftMouseDownSent = SDL_FALSE;
                twoFingerTouch = SDL_FALSE;
            }
            rightFingerDown = 0;
        }


        CGPoint locationInView = [self touchLocation:touch shouldNormalize:YES];
#ifdef IPHONE_TOUCH_EFFICIENT_DANGEROUS
        SDL_SendFingerDown(touchId, (long)touch,
                           SDL_FALSE, locationInView.x, locationInView.y,
                           1);
#else
        int i;
        for (i = 0; i < MAX_SIMULTANEOUS_TOUCHES; i++) {
            if (finger[i] == touch) {
                SDL_SendFingerDown(touchId, i,
                                   SDL_FALSE, locationInView.x, locationInView.y,
                                   1);
                finger[i] = NULL;
                break;
            }
        }
#endif
        touch = (UITouch*)[enumerator nextObject];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    /*
        this can happen if the user puts more than 5 touches on the screen
        at once, or perhaps in other circumstances.  Usually (it seems)
        all active touches are canceled.
    */
    [self touchesEnded: touches withEvent: event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    NSEnumerator *enumerator = [touches objectEnumerator];
    UITouch *touch = (UITouch*)[enumerator nextObject];

    while (touch) {
        if ((SDL_FingerID)touch == leftFingerDown) {
            CGPoint locationInView = [self touchLocation:touch shouldNormalize:NO];

            /* send moved event */
            SDL_SendMouseMotion(NULL, 0, locationInView.x, locationInView.y);
        }

        CGPoint locationInView = [self touchLocation:touch shouldNormalize:YES];
#ifdef IPHONE_TOUCH_EFFICIENT_DANGEROUS
        SDL_SendTouchMotion(touchId, (long)touch,
                            SDL_FALSE, locationInView.x, locationInView.y,
                            1);
#else
        int i;
        for (i = 0; i < MAX_SIMULTANEOUS_TOUCHES; i++) {
            if (finger[i] == touch) {
                SDL_SendTouchMotion(touchId, i,
                                    SDL_FALSE, locationInView.x, locationInView.y,
                                    1);
                break;
            }
        }
#endif
        touch = (UITouch*)[enumerator nextObject];
    }
}

/*
    ---- Keyboard related functionality below this line ----
*/
#if SDL_IPHONE_KEYBOARD

/* Is the iPhone virtual keyboard visible onscreen? */
- (BOOL)keyboardVisible
{
    return keyboardVisible;
}

/* Set ourselves up as a UITextFieldDelegate */
- (void)initializeKeyboard
{
    textField = [[UITextField alloc] initWithFrame: CGRectZero];
    textField.delegate = self;
    /* placeholder so there is something to delete! */
    textField.text = @" ";

    /* set UITextInputTrait properties, mostly to defaults */
    textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textField.autocorrectionType = UITextAutocorrectionTypeNo;
    textField.enablesReturnKeyAutomatically = NO;
    textField.keyboardAppearance = UIKeyboardAppearanceDefault;
    textField.keyboardType = UIKeyboardTypeDefault;
    textField.returnKeyType = UIReturnKeyDefault;
    textField.secureTextEntry = NO;

    textField.hidden = YES;
    keyboardVisible = NO;
    /* add the UITextField (hidden) to our view */
    [self addSubview: textField];
    [textField release];
}

/* reveal onscreen virtual keyboard */
- (void)showKeyboard
{
    keyboardVisible = YES;
    [textField becomeFirstResponder];
}

/* hide onscreen virtual keyboard */
- (void)hideKeyboard
{
    keyboardVisible = NO;
    [textField resignFirstResponder];
}

/* UITextFieldDelegate method.  Invoked when user types something. */
- (BOOL)textField:(UITextField *)_textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    if ([string length] == 0) {
        /* it wants to replace text with nothing, ie a delete */
        SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_BACKSPACE);
        SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_BACKSPACE);
    }
    else {
        /* go through all the characters in the string we've been sent
           and convert them to key presses */
        int i;
        for (i = 0; i < [string length]; i++) {

            unichar c = [string characterAtIndex: i];

            Uint16 mod = 0;
            SDL_Scancode code;

            if (c < 127) {
                /* figure out the SDL_Scancode and SDL_keymod for this unichar */
                code = unicharToUIKeyInfoTable[c].code;
                mod  = unicharToUIKeyInfoTable[c].mod;
            }
            else {
                /* we only deal with ASCII right now */
                code = SDL_SCANCODE_UNKNOWN;
                mod = 0;
            }

            if (mod & KMOD_SHIFT) {
                /* If character uses shift, press shift down */
                SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_LSHIFT);
            }
            /* send a keydown and keyup even for the character */
            SDL_SendKeyboardKey(SDL_PRESSED, code);
            SDL_SendKeyboardKey(SDL_RELEASED, code);
            if (mod & KMOD_SHIFT) {
                /* If character uses shift, press shift back up */
                SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_LSHIFT);
            }
        }
        SDL_SendKeyboardText([string UTF8String]);
    }
    return NO; /* don't allow the edit! (keep placeholder text there) */
}

/* Terminates the editing session */
- (BOOL)textFieldShouldReturn:(UITextField*)_textField
{
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_RETURN);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_RETURN);
    [self hideKeyboard];
    return YES;
}

#endif

@end

/* iPhone keyboard addition functions */
#if SDL_IPHONE_KEYBOARD

static SDL_uikitview * getWindowView(SDL_Window * window)
{
    if (window == NULL) {
        SDL_SetError("Window does not exist");
        return nil;
    }

    SDL_WindowData *data = (SDL_WindowData *)window->driverdata;
    SDL_uikitview *view = data != NULL ? data->view : nil;

    if (view == nil) {
        SDL_SetError("Window has no view");
    }

    return view;
}

SDL_bool UIKit_HasScreenKeyboardSupport(_THIS, SDL_Window *window)
{
    SDL_uikitview *view = getWindowView(window);
    if (view == nil) {
        return SDL_FALSE;
    }

    return SDL_TRUE;
}

int UIKit_ShowScreenKeyboard(_THIS, SDL_Window *window)
{
    SDL_uikitview *view = getWindowView(window);
    if (view == nil) {
        return -1;
    }

    [view showKeyboard];
    return 0;
}

int UIKit_HideScreenKeyboard(_THIS, SDL_Window *window)
{
    SDL_uikitview *view = getWindowView(window);
    if (view == nil) {
        return -1;
    }

    [view hideKeyboard];
    return 0;
}

SDL_bool UIKit_IsScreenKeyboardShown(_THIS, SDL_Window *window)
{
    SDL_uikitview *view = getWindowView(window);
    if (view == nil) {
        return 0;
    }

    return view.keyboardVisible;
}

int UIKit_ToggleScreenKeyboard(_THIS, SDL_Window *window)
{
    SDL_uikitview *view = getWindowView(window);
    if (view == nil) {
        return -1;
    }

    if (UIKit_IsScreenKeyboardShown(_this, window)) {
        UIKit_HideScreenKeyboard(_this, window);
    }
    else {
        UIKit_ShowScreenKeyboard(_this, window);
    }
    return 0;
}

#endif /* SDL_IPHONE_KEYBOARD */

#endif /* SDL_VIDEO_DRIVER_UIKIT */

/* vi: set ts=4 sw=4 expandtab: */
