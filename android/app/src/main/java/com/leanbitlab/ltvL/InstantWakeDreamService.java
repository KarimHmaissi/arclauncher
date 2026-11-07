/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package com.omeda.arc;

import android.service.dreams.DreamService;
import android.view.KeyEvent;
import android.view.MotionEvent;

/**
 * A screensaver that wakes instantly: the first key, touch or other input
 * finishes the dream at once, with no exit fade, and is consumed so it never
 * reaches Home.
 */
public abstract class InstantWakeDreamService extends DreamService {
    private boolean exiting;

    @Override
    public void onAttachedToWindow() {
        super.onAttachedToWindow();
        // Every input is a wake signal; nothing in the dream is interactive.
        setInteractive(false);
        setFullscreen(true);
        // Replace the framework's dream enter/exit and activity close animations
        // with none. Not 0: zero falls back to the default activity animations.
        getWindow().setWindowAnimations(R.style.DreamNoAnimation);
    }

    /** True once the dream is finishing; late callbacks should do nothing. */
    protected final boolean isExiting() {
        return exiting;
    }

    /** Subclasses stop handlers and animators here. Called once, before finish(). */
    protected void onExitNow() {
    }

    private boolean exitNow() {
        if (!exiting) {
            exiting = true;
            onExitNow();
            // finish() stops the dream immediately. The default wakeUp() path is
            // the one that gives a dream time to fade itself out.
            finish();
        }
        // Consume the event (and the matching key up): the waking key never acts on Home.
        return true;
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        return exitNow();
    }

    @Override
    public boolean dispatchKeyShortcutEvent(KeyEvent event) {
        return exitNow();
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        return exitNow();
    }

    @Override
    public boolean dispatchTrackballEvent(MotionEvent event) {
        return exitNow();
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent event) {
        return exitNow();
    }
}
