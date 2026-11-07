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

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Random;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * "Arc Photos": the 4K photos Arc keeps for its wallpaper, crossfading slowly,
 * with Arc's clock style and the photo credit. Reads only from disk: Arc's
 * wallpaper service downloads the photos into app_flutter/photo_wallpaper.
 */
public class PhotoScreensaverService extends InstantWakeDreamService {
    private static final long PHOTO_INTERVAL_MS = 180_000;
    /** While no photo is on screen, look for one this often (the pool may be filling). */
    private static final long EMPTY_RECHECK_MS = 20_000;
    private static final long CROSSFADE_MS = 2_500;
    private static final long ENTER_FADE_MS = 1_200;
    private static final int BURN_IN_SHIFT_PX = 24;
    private static final int SHOWN_HISTORY_MAX = 100;

    private static final String FLUTTER_PREFS = "FlutterSharedPreferences";
    private static final String OWN_PREFS = "arc_photo_screensaver";
    private static final String KEY_SHOWN = "shown_order";
    private static final String KEY_LAST_DREAM = "last_dream_at";
    /** A dream this recent means the screensaver is in use, so Arc keeps its photos fresh. */
    private static final long IN_USE_WINDOW_MS = 7L * 24 * 60 * 60 * 1000;

    private final Random random = new Random();

    private FrameLayout root;
    private ImageView front;
    private ImageView back;
    private LinearLayout clock;
    private TextView timeView;
    private TextView dateView;
    private LinearLayout credit;
    private TextView creditTitle;
    private TextView creditCopyright;

    private Handler handler;
    private ExecutorService decoder;
    private Bitmap shownBitmap;
    private Bitmap pendingOld;
    private String shownId;
    private boolean fading;
    private boolean decoding;
    /** Set once the dream is ending, by input or by the system; late callbacks then do nothing. */
    private boolean stopped;
    /** Ids shown, least recent first; kept across sessions so each one starts somewhere new. */
    private final List<String> shownOrder = new ArrayList<>();

    private final Runnable photoTick = new Runnable() {
        @Override
        public void run() {
            showNextPhoto();
            handler.postDelayed(this, shownBitmap == null ? EMPTY_RECHECK_MS : PHOTO_INTERVAL_MS);
        }
    };

    private final Runnable clockTick = new Runnable() {
        @Override
        public void run() {
            updateClock();
            long now = System.currentTimeMillis();
            handler.postDelayed(this, 60_000 - (now % 60_000));
        }
    };

    @Override
    public void onAttachedToWindow() {
        super.onAttachedToWindow();

        handler = new Handler(Looper.getMainLooper());
        decoder = Executors.newSingleThreadExecutor();
        stopped = false;
        loadShownOrder();
        getSharedPreferences(OWN_PREFS, MODE_PRIVATE).edit()
                .putLong(KEY_LAST_DREAM, System.currentTimeMillis()).apply();

        root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        back = newImageView();
        front = newImageView();
        root.addView(back);
        root.addView(front);

        int margin = dp(48);
        clock = new LinearLayout(this);
        clock.setOrientation(LinearLayout.VERTICAL);
        timeView = newText(56, Color.WHITE);
        dateView = newText(22, Color.WHITE);
        clock.addView(timeView);
        clock.addView(dateView);
        FrameLayout.LayoutParams clockParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.START);
        clockParams.setMargins(margin, margin, margin, margin);
        root.addView(clock, clockParams);

        credit = new LinearLayout(this);
        credit.setOrientation(LinearLayout.VERTICAL);
        credit.setGravity(Gravity.END);
        int creditColor = 0xB3FFFFFF; // white at 70%
        creditTitle = newText(14, creditColor);
        creditCopyright = newText(14, creditColor);
        int maxCreditWidth = getResources().getDisplayMetrics().widthPixels * 2 / 5;
        for (TextView tv : new TextView[] {creditTitle, creditCopyright}) {
            tv.setMaxLines(1);
            tv.setEllipsize(TextUtils.TruncateAt.END);
            tv.setMaxWidth(maxCreditWidth);
            tv.setGravity(Gravity.END);
            credit.addView(tv);
        }
        FrameLayout.LayoutParams creditParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.END);
        creditParams.setMargins(margin, margin, margin, margin);
        root.addView(credit, creditParams);
        credit.setVisibility(View.GONE);

        setContentView(root);

        // Only our content fades in when the dream starts; the exit stays instant.
        root.setAlpha(0f);
        root.animate().alpha(1f).setDuration(ENTER_FADE_MS);

        updateClockVisibility();
        handler.post(clockTick);
        handler.post(photoTick);
    }

    private ImageView newImageView() {
        ImageView view = new ImageView(this);
        view.setScaleType(ImageView.ScaleType.CENTER_CROP);
        view.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        return view;
    }

    private TextView newText(int sp, int color) {
        TextView tv = new TextView(this);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        tv.setTextColor(color);
        // Readable on bright photos.
        tv.setShadowLayer(12, 0, 2, 0x99000000);
        return tv;
    }

    private int dp(int value) {
        return Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, value, getResources().getDisplayMetrics()));
    }

    // Photos

    private File photoDir() {
        return new File(getDir("flutter", MODE_PRIVATE), "photo_wallpaper");
    }

    /** Cached photos, newest first. Temp files (.part) are ignored. */
    private List<File> cachedPhotos() {
        File[] files = photoDir().listFiles((dir, name) -> name.endsWith(".jpg"));
        if (files == null) return new ArrayList<>();
        List<File> list = new ArrayList<>(Arrays.asList(files));
        list.sort((a, b) -> Long.compare(b.lastModified(), a.lastModified()));
        return list;
    }

    private static String idOf(File f) {
        String name = f.getName();
        return name.endsWith(".jpg") ? name.substring(0, name.length() - 4) : name;
    }

    /**
     * The next photo: never shown first (newest of those), else the one shown
     * longest ago. Never the one on screen. Null when there is no other photo.
     */
    private File pickNext(List<File> newestFirst) {
        File best = null;
        int bestRank = 0;
        for (File f : newestFirst) {
            String id = idOf(f);
            if (id.equals(shownId)) continue;
            int rank = shownOrder.indexOf(id);
            if (best == null || rank < bestRank) {
                best = f;
                bestRank = rank;
            }
        }
        return best;
    }

    private boolean isStopped() {
        return stopped || isExiting();
    }

    /**
     * Whether Arc Photos is the chosen screensaver, or has run lately (some
     * Android versions don't let apps read the choice). Arc keeps the photo pool
     * filled while it is, even with the 4K wallpaper off.
     */
    static boolean isInUse(Context context) {
        try {
            String components = Settings.Secure.getString(context.getContentResolver(), "screensaver_components");
            if (components != null) {
                for (String flat : components.split(",")) {
                    ComponentName name = ComponentName.unflattenFromString(flat.trim());
                    if (name != null
                            && name.getPackageName().equals(context.getPackageName())
                            && name.getClassName().equals(PhotoScreensaverService.class.getName())) {
                        return true;
                    }
                }
            }
        } catch (Exception ignored) {
            // Not readable here: fall back to when the dream last ran.
        }
        long last = context.getSharedPreferences(OWN_PREFS, MODE_PRIVATE).getLong(KEY_LAST_DREAM, 0);
        return System.currentTimeMillis() - last < IN_USE_WINDOW_MS;
    }

    private void showNextPhoto() {
        if (isStopped() || fading || decoding) return;
        List<File> photos = cachedPhotos();
        if (photos.isEmpty()) {
            // Nothing cached yet: black with the clock, shifted against burn-in.
            shiftOverlays();
            updateClockVisibility();
            return;
        }
        File next = pickNext(photos);
        if (next == null) return; // The only photo is already on screen.

        final String id = idOf(next);
        final String path = next.getAbsolutePath();
        final DisplayMetrics metrics = getResources().getDisplayMetrics();
        final int targetWidth = metrics.widthPixels;
        final int targetHeight = metrics.heightPixels;
        decoding = true;
        try {
            decoder.execute(() -> {
                Bitmap bitmap = decode(path, targetWidth, targetHeight);
                handler.post(() -> {
                    decoding = false;
                    // A decode can't be interrupted, so it may land after the dream ended.
                    if (isStopped() || bitmap == null) {
                        if (bitmap != null) bitmap.recycle();
                        return;
                    }
                    show(bitmap, id);
                });
            });
        } catch (Exception ignored) {
            // The decoder was shut down: the dream is ending.
            decoding = false;
        }
    }

    /** Decodes at the screen's size, not 3840x2160 (about 8 MB instead of 33 MB on 1080p). */
    private static Bitmap decode(String path, int width, int height) {
        try {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(path, bounds);
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null;
            int sample = 1;
            while (bounds.outWidth / (sample * 2) >= width && bounds.outHeight / (sample * 2) >= height) {
                sample *= 2;
            }
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = sample;
            options.inPreferredConfig = Bitmap.Config.ARGB_8888;
            return BitmapFactory.decodeFile(path, options); // null on a corrupt file: skip this tick
        } catch (Throwable e) {
            return null;
        }
    }

    private void show(Bitmap bitmap, String id) {
        markShown(id);
        shownId = id;
        updateCredit(id);
        shiftOverlays();
        updateClockVisibility();

        if (shownBitmap == null) {
            // First photo: fade it in over black (the enter fade may be long over
            // when the pool was empty at first).
            shownBitmap = bitmap;
            front.setImageBitmap(bitmap);
            front.setAlpha(0f);
            fading = true;
            front.animate().alpha(1f).setDuration(ENTER_FADE_MS).setListener(new AnimatorListenerAdapter() {
                @Override
                public void onAnimationEnd(Animator animation) {
                    front.animate().setListener(null);
                    fading = false;
                }
            });
            return;
        }

        // The new photo goes under the current one, which then fades out.
        fading = true;
        pendingOld = shownBitmap;
        shownBitmap = bitmap;
        back.setAlpha(1f);
        back.setImageBitmap(bitmap);
        front.animate().alpha(0f).setDuration(CROSSFADE_MS).setListener(new AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                front.animate().setListener(null);
                if (isStopped()) return;
                ImageView old = front;
                front = back;
                back = old;
                // Keep the shown photo on top: the old view goes to the bottom, empty.
                root.removeView(old);
                root.addView(old, 0);
                old.setImageDrawable(null);
                old.setAlpha(1f);
                if (pendingOld != null) {
                    pendingOld.recycle();
                    pendingOld = null;
                }
                fading = false;
            }
        });
    }

    private void markShown(String id) {
        shownOrder.remove(id);
        shownOrder.add(id);
        while (shownOrder.size() > SHOWN_HISTORY_MAX) shownOrder.remove(0);
        getSharedPreferences(OWN_PREFS, MODE_PRIVATE).edit()
                .putString(KEY_SHOWN, TextUtils.join("\n", shownOrder)).apply();
    }

    private void loadShownOrder() {
        shownOrder.clear();
        String saved = getSharedPreferences(OWN_PREFS, MODE_PRIVATE).getString(KEY_SHOWN, "");
        if (saved == null || saved.isEmpty()) return;
        shownOrder.addAll(Arrays.asList(saved.split("\n")));
    }

    // Overlays

    private SharedPreferences flutterPrefs() {
        return getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE);
    }

    private boolean prefBool(String key, boolean fallback) {
        try {
            return flutterPrefs().getBoolean(key, fallback);
        } catch (ClassCastException e) {
            return fallback;
        }
    }

    private String prefString(String key, String fallback) {
        try {
            String value = flutterPrefs().getString(key, fallback);
            return value == null ? fallback : value;
        } catch (ClassCastException e) {
            return fallback;
        }
    }

    private void updateClockVisibility() {
        // Always show the clock while there is no photo, so the screen isn't just black.
        boolean show = shownBitmap == null || prefBool("flutter.photo_screensaver_clock", true);
        clock.setVisibility(show ? View.VISIBLE : View.GONE);
    }

    private void updateClock() {
        if (timeView == null) return;
        android.graphics.Typeface typeface =
                ClockScreensaverService.typefaceFor(prefString("flutter.screensaver_clock_style", "minimal"));
        timeView.setTypeface(typeface);
        dateView.setTypeface(typeface);
        Date now = new Date();
        timeView.setText(format(prefString("flutter.time_format", "H:mm"), "H:mm", now));
        dateView.setText(format(prefString("flutter.date_format", "EEEE d"), "EEEE d", now));
    }

    private static String format(String pattern, String fallback, Date date) {
        try {
            return new SimpleDateFormat(pattern, Locale.getDefault()).format(date);
        } catch (IllegalArgumentException e) {
            return new SimpleDateFormat(fallback, Locale.getDefault()).format(date);
        }
    }

    private void updateCredit(String id) {
        JSONObject entry = null;
        if (prefBool("flutter.photo_wallpaper_show_credit", true)) {
            try {
                entry = new JSONObject(prefString("flutter.photo_wallpaper_credits", "{}")).optJSONObject(id);
            } catch (JSONException e) {
                entry = null;
            }
        }
        if (entry == null) {
            credit.setVisibility(View.GONE);
            return;
        }
        creditTitle.setText(entry.optString("title", ""));
        creditCopyright.setText(entry.optString("copyright", ""));
        credit.setVisibility(View.VISIBLE);
    }

    /** Moves the clock and credit a few pixels on each change, against burn-in. */
    private void shiftOverlays() {
        for (View view : new View[] {clock, credit}) {
            view.setTranslationX(random.nextInt(BURN_IN_SHIFT_PX + 1) * (view == credit ? -1 : 1));
            view.setTranslationY(-random.nextInt(BURN_IN_SHIFT_PX + 1));
        }
    }

    // Cleanup

    private void stopEverything() {
        stopped = true;
        if (handler != null) handler.removeCallbacksAndMessages(null);
        if (root != null) root.animate().cancel();
        if (front != null) {
            front.animate().setListener(null);
            front.animate().cancel();
        }
        if (decoder != null) decoder.shutdownNow();
    }

    @Override
    protected void onExitNow() {
        stopEverything();
    }

    @Override
    public void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        // Also when the system stopped the dream without any input.
        stopEverything();
        // Recycle only after the views have dropped the bitmaps.
        if (front != null) front.setImageDrawable(null);
        if (back != null) back.setImageDrawable(null);
        if (pendingOld != null) {
            pendingOld.recycle();
            pendingOld = null;
        }
        if (shownBitmap != null) {
            shownBitmap.recycle();
            shownBitmap = null;
        }
    }
}
