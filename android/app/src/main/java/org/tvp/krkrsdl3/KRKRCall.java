package org.tvp.krkrsdl3;

import android.app.Activity;
import android.app.AlertDialog;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.EditText;
import android.widget.PopupMenu;
import java.lang.ref.WeakReference;
import java.util.concurrent.CountDownLatch;

/** Android UI callbacks expected by the upstream engine, hosted by Flutter. */
public final class KRKRCall {
    private static WeakReference<Activity> activity = new WeakReference<>(null);
    private static volatile String inputResult = "";
    private static volatile int inputResultCode = -1;
    private static volatile CountDownLatch inputLatch = new CountDownLatch(0);
    private static volatile boolean menuOpen = false;

    private KRKRCall() {}

    public static void attach(Activity host) {
        activity = new WeakReference<>(host);
    }

    public static void detach(Activity host) {
        if (activity.get() != host) return;
        activity = new WeakReference<>(null);
        inputLatch.countDown();
        if (menuOpen) nativeOnMenuDismiss();
        menuOpen = false;
    }

    public static void ShowInputBox(String title, String prompt, String text, String[] buttons) {
        Activity host = activity.get();
        inputResult = "";
        inputResultCode = -1;
        inputLatch = new CountDownLatch(1);
        if (host == null) {
            inputLatch.countDown();
            return;
        }
        host.runOnUiThread(() -> {
            EditText input = new EditText(host);
            input.setText(text);
            AlertDialog.Builder dialog = new AlertDialog.Builder(host)
                .setTitle(title)
                .setMessage(prompt)
                .setView(input)
                .setOnCancelListener(ignored -> inputLatch.countDown());
            String positive = buttons.length > 0 ? buttons[0] : "OK";
            dialog.setPositiveButton(positive, (ignored, which) -> {
                inputResult = input.getText().toString();
                inputResultCode = 0;
                inputLatch.countDown();
            });
            if (buttons.length > 1) {
                dialog.setNegativeButton(buttons[1], (ignored, which) -> {
                    inputLatch.countDown();
                });
            }
            dialog.show();
        });
    }

    public static int WaitInputResult() {
        try {
            inputLatch.await();
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            return -1;
        }
        return inputResultCode;
    }

    public static String GetInputResult() {
        return inputResult;
    }

    public enum MenuItemType { NORMAL, CHECKBOX, SUBMENU, SEPARATOR }

    public static final class MenuItemData {
        public int id;
        public String caption;
        public MenuItemType type = MenuItemType.NORMAL;
        public boolean checked;
        public int order;
        public MenuItemData[] children;

        public MenuItemData(int id, String caption) {
            this.id = id;
            this.caption = caption;
        }
    }

    private static void populate(Menu menu, MenuItemData[] items) {
        if (items == null) return;
        for (MenuItemData item : items) {
            if (item == null) continue;
            if (item.type == MenuItemType.SEPARATOR || "-".equals(item.caption)) {
                menu.add(0, item.id, item.order, "────────").setEnabled(false);
                continue;
            }
            MenuItem entry = menu.add(0, item.id, item.order, item.caption);
            entry.setCheckable(item.type == MenuItemType.CHECKBOX);
            entry.setChecked(item.checked);
        }
    }

    private static native void nativeOnMenuItemClick(int itemId, String caption);
    private static native void nativeOnMenuDismiss();

    public static void showDynamicMenu(int x, int y, MenuItemData[] items) {
        Activity host = activity.get();
        if (host == null) {
            nativeOnMenuDismiss();
            return;
        }
        menuOpen = true;
        host.runOnUiThread(() -> {
            View anchor = host.getWindow().getDecorView();
            PopupMenu popup = new PopupMenu(host, anchor);
            populate(popup.getMenu(), items);
            final boolean[] clicked = {false};
            popup.setOnMenuItemClickListener(item -> {
                clicked[0] = true;
                menuOpen = false;
                nativeOnMenuItemClick(item.getItemId(), item.getTitle().toString());
                return true;
            });
            popup.setOnDismissListener(ignored -> {
                if (!clicked[0]) {
                    menuOpen = false;
                    nativeOnMenuDismiss();
                }
            });
            popup.show();
        });
    }
}
