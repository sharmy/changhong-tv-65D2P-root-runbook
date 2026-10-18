package org.sharmy.chsource;

import android.app.IntentService;
import android.content.Intent;
import android.util.Log;

/**
 * 自愈执行体（由 BootReceiver 或手动 __HEAL__ 拉起）。
 * 真正的逻辑都在 {@link Healer} 里，这里只负责在后台线程跑起来。
 */
public class SelfHealService extends IntentService {

    private static final String TAG = "ChSourceHeal";

    public SelfHealService() {
        super("SelfHealService");
    }

    @Override
    protected void onHandleIntent(Intent intent) {
        String trigger = intent == null ? "manual"
                : intent.getStringExtra("trigger");
        if (trigger == null || trigger.length() == 0) {
            trigger = "manual";
        }
        try {
            Healer.schedule(getApplicationContext());
            Healer.run(getApplicationContext(), trigger);
        } catch (Throwable t) {
            Log.e(TAG, "自愈异常", t);
        }
    }
}
